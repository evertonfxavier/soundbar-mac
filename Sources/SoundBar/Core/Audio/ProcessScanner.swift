import AppKit
import CoreAudio
import Darwin

/// One Core Audio "process object": a process that has done audio IO.
struct AudioProcess {
    let objectID: AudioObjectID
    let pid: pid_t
    let isRunningOutput: Bool
    let isRunningInput: Bool
    let outputDeviceUID: String?
}

/// The user-facing app that owns one or more audio processes
/// (e.g. Chrome owns its "Google Chrome Helper" audio process).
struct AppOwner {
    let id: String
    let name: String
    let icon: NSImage?
}

enum ProcessScanner {
    static func scan() -> [AudioProcess] {
        let ids: [AudioObjectID] = CA.getArray(CA.system, kAudioHardwarePropertyProcessObjectList, initial: 0)
        return ids.compactMap { id in
            guard let pid: pid_t = CA.get(id, kAudioProcessPropertyPID, initial: -1), pid > 0 else { return nil }
            let out = (CA.get(id, kAudioProcessPropertyIsRunningOutput, initial: UInt32(0)) ?? 0) != 0
            let inp = (CA.get(id, kAudioProcessPropertyIsRunningInput, initial: UInt32(0)) ?? 0) != 0
            var outUID: String?
            if out {
                let devices: [AudioObjectID] = CA.getArray(
                    id, kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeOutput, initial: 0)
                outUID = devices.lazy.compactMap { CA.deviceUID($0) }.first
            }
            return AudioProcess(
                objectID: id, pid: pid, isRunningOutput: out, isRunningInput: inp, outputDeviceUID: outUID)
        }
    }

    // MARK: - Owner resolution

    private typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t
    private static let responsibleFn: ResponsibleFn? = {
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
        guard let sym = dlsym(rtldDefault, "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(sym, to: ResponsibleFn.self)
    }()

    private static var cache: [pid_t: AppOwner] = [:]

    static func owner(for pid: pid_t) -> AppOwner {
        if let cached = cache[pid] { return cached }
        let owner = resolveOwner(pid)
        cache[pid] = owner
        return owner
    }

    static func forget(pidsNotIn alive: Set<pid_t>) {
        cache = cache.filter { alive.contains($0.key) }
    }

    private static func resolveOwner(_ pid: pid_t) -> AppOwner {
        var candidates: [pid_t] = []
        if let f = responsibleFn {
            let r = f(pid)
            if r > 0 { candidates.append(r) }
        }
        candidates.append(pid)
        var p = pid
        for _ in 0..<10 {
            let pp = parentPID(p)
            if pp <= 1 { break }
            candidates.append(pp)
            p = pp
        }

        let apps = candidates.compactMap { NSRunningApplication(processIdentifier: $0) }
        if let app = apps.first(where: { $0.activationPolicy == .regular }) ?? apps.first {
            let id = app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
            let name = app.localizedName ?? app.bundleIdentifier ?? processName(pid)
            return AppOwner(id: id, name: name, icon: app.icon)
        }
        let name = processName(pid)
        return AppOwner(id: "proc:\(name)", name: name, icon: nil)
    }

    private static func parentPID(_ pid: pid_t) -> pid_t {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let r = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        return r == size ? pid_t(info.pbi_ppid) : -1
    }

    private static func processName(_ pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: 1024)
        if proc_name(pid, &buf, UInt32(buf.count)) > 0 {
            return String(cString: buf)
        }
        return "PID \(pid)"
    }
}
