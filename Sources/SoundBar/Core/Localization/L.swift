import Foundation

/// Every text the user reads, in the three languages next to each other. The `switch` is exhaustive, so a new text
/// that lacks a language does not compile; a few take arguments, written `%@` in every language, in the same order.
enum L: CaseIterable {
    // The menu
    case output, microphone
    case switchDevice, deviceOf, volumeOf
    case mute, unmute, muteThing, unmuteThing, microphoneOfThing
    case sectionChromeTabs, sectionApps, sectionSoundboard
    case noAppsPlaying, extensionHint
    case micInUseBy, micMutedFor
    case checkForUpdates, checkForUpdatesHelp, launchAtLogin, quit
    case languageLabel, languageAutomatic
    case playingAudio, usingMicrophone, mutedLabel, doubleClickReset, doubleClickRestore
    // Permission and updates
    case permissionNeeded, permissionBody, openSettings, allow
    case newVersion, updateBody, download, whatsNew
    // The soundboard
    case stopAllSounds, addSound, noSoundsYet, edit, remove
    case statusNoDriver, copyCommand, website, statusIdle, statusLive
    case soundsMicrophone, automaticSystem, noMicrophoneFound, couldNotPlaySound
    // The sound editor
    case newSound, editSound, fieldName, namePlaceholder, fieldSound, choose, fieldIcon
    case emojiOption, imageOption, chooseImage, change, fieldVolume, listen, cancel, save
    case noFileChosen, keepCurrentSound, chooseSoundPanel, couldNotPlayFile
    // Errors
    case errChooseAudio, errImageUnreadable, errAudioUnreadable, errSoundTooLong
    case errDeviceMissing, errStepFailed, stepCreateAggregate, stepCreateIOProc, stepStartAudio
    case errTrimEmpty, errExportFailed, errNotALibrary
    // The soundboard: groups, search, volume, the call
    case collapseSection, expandSection, sectionExpanded, sectionCollapsed
    case searchSounds, allGroups, masterVolume, sendToCall, sendToCallHelp
    case muteCall, unmuteCall, callMutedStatus, moveEarlier, moveLater
    // The library: more actions, export and import
    case libraryMenu, exportLibrary, importLibrary, importResult, exportFilePrompt, importFilePrompt
    // The sound editor: group, section, volume, shortcut
    case fieldGroup, groupPlaceholder, fieldTrim, trimStart, trimEnd, secondsValue, normalizeVolume, normalizeHelp
    case fieldShortcut, recordShortcut, pressShortcut, clearShortcut, noShortcut
    // Shortcuts
    case shortcutsMenu, shortcutsTitle, shortcutsHelp, actionStopAll, actionCallMute, actionMicMute
    case shortcutNeedsModifier, shortcutInUse, shortcutUnavailable

    /// The text in Portuguese, English and Spanish.
    var translations: (pt: String, en: String, es: String) {
        switch self {
        case .output: ("Saída", "Output", "Salida")
        case .microphone: ("Microfone", "Microphone", "Micrófono")
        case .switchDevice: ("Trocar %@", "Switch %@", "Cambiar %@")
        case .deviceOf: ("Dispositivo de %@: %@", "%@ device: %@", "Dispositivo de %@: %@")
        case .volumeOf: ("Volume de %@", "%@ volume", "Volumen de %@")
        case .mute: ("Mutar", "Mute", "Silenciar")
        case .unmute: ("Desmutar", "Unmute", "Activar sonido")
        case .muteThing: ("Mutar %@", "Mute %@", "Silenciar %@")
        case .unmuteThing: ("Desmutar %@", "Unmute %@", "Activar el sonido de %@")
        case .microphoneOfThing: ("microfone de %@", "microphone of %@", "micrófono de %@")
        case .sectionChromeTabs: ("ABAS DO CHROME", "CHROME TABS", "PESTAÑAS DE CHROME")
        case .sectionApps: ("APPS", "APPS", "APPS")
        case .sectionSoundboard: ("SONOPLASTIA", "SOUNDBOARD", "EFECTOS DE SONIDO")
        case .noAppsPlaying:
            (
                "Nenhum app usando áudio agora.", "No app is using audio right now.",
                "Ninguna app está usando audio ahora."
            )
        case .extensionHint:
            (
                "Para controlar cada aba do Chrome, instale a extensão SoundBar Bridge (veja o README).",
                "To control each Chrome tab, install the SoundBar Bridge extension (see the README).",
                "Para controlar cada pestaña de Chrome, instala la extensión SoundBar Bridge (consulta el README)."
            )
        case .micInUseBy: ("Em uso por: ", "In use by: ", "En uso por: ")
        case .micMutedFor: ("Mutado para: ", "Muted for: ", "Silenciado para: ")
        case .checkForUpdates: ("Verificar atualizações", "Check for updates", "Buscar actualizaciones")
        case .checkForUpdatesHelp:
            (
                "Consulta o GitHub de tempos em tempos para saber se há uma versão nova",
                "Asks GitHub from time to time whether there is a new version",
                "Consulta GitHub de vez en cuando para saber si hay una versión nueva"
            )
        case .launchAtLogin: ("Abrir ao iniciar sessão", "Open at login", "Abrir al iniciar sesión")
        case .quit: ("Sair", "Quit", "Salir")
        case .languageLabel: ("Idioma", "Language", "Idioma")
        case .languageAutomatic: ("Automático", "Automatic", "Automático")
        case .playingAudio: ("Tocando áudio", "Playing audio", "Reproduciendo audio")
        case .usingMicrophone: ("Usando o microfone", "Using the microphone", "Usando el micrófono")
        case .mutedLabel: ("mudo", "muted", "silenciado")
        case .doubleClickReset:
            ("Clique duplo para voltar a 100%", "Double-click to go back to 100%", "Doble clic para volver al 100%")
        case .doubleClickRestore:
            ("Clique duplo para restaurar", "Double-click to restore", "Doble clic para restaurar")

        case .permissionNeeded: ("Permissão necessária", "Permission needed", "Permiso necesario")
        case .permissionBody:
            (
                "Para ajustar o volume de cada app, permita “Gravação de Áudio do Sistema”.",
                "To adjust the volume of each app, allow “System Audio Recording”.",
                "Para ajustar el volumen de cada app, permite “Grabación de audio del sistema”."
            )
        case .openSettings: ("Abrir Ajustes", "Open Settings", "Abrir Ajustes")
        case .allow: ("Permitir", "Allow", "Permitir")
        case .newVersion: ("Nova versão: v%@", "New version: v%@", "Nueva versión: v%@")
        case .updateBody:
            (
                "Você está na v%@. Baixe o instalador e abra-o como da primeira vez.",
                "You are on v%@. Download the installer and open it as the first time.",
                "Estás en la v%@. Descarga el instalador y ábrelo como la primera vez."
            )
        case .download: ("Baixar", "Download", "Descargar")
        case .whatsNew: ("Novidades", "What's new", "Novedades")

        case .stopAllSounds: ("Parar todos os sons", "Stop all sounds", "Detener todos los sonidos")
        case .addSound: ("Adicionar um som", "Add a sound", "Añadir un sonido")
        case .noSoundsYet:
            (
                "Nenhum som ainda. Toque em + para adicionar o primeiro.",
                "No sounds yet. Tap + to add the first one.",
                "Aún no hay sonidos. Toca + para añadir el primero."
            )
        case .edit: ("Editar…", "Edit…", "Editar…")
        case .remove: ("Remover", "Remove", "Eliminar")
        case .statusNoDriver:
            (
                "A sonoplastia precisa do BlackHole (um microfone virtual gratuito). Instale para ativar.",
                "The soundboard needs BlackHole (a free virtual microphone). Install it to turn it on.",
                "Los efectos de sonido necesitan BlackHole (un micrófono virtual gratuito). Instálalo para activarlos."
            )
        case .copyCommand: ("Copiar comando", "Copy command", "Copiar comando")
        case .website: ("Site", "Website", "Sitio web")
        case .statusIdle:
            (
                "Na chamada, escolha “BlackHole 2ch” como microfone para os outros ouvirem os sons.",
                "In the call, choose “BlackHole 2ch” as the microphone so the others hear the sounds.",
                "En la llamada, elige “BlackHole 2ch” como micrófono para que los demás oigan los sonidos."
            )
        case .statusLive:
            ("Os sons vão para a chamada.", "The sounds are going into the call.", "Los sonidos van a la llamada.")
        case .soundsMicrophone: ("Microfone dos sons:", "Microphone for the sounds:", "Micrófono de los sonidos:")
        case .automaticSystem:
            ("Automático (o do sistema)", "Automatic (the system's)", "Automático (el del sistema)")
        case .noMicrophoneFound:
            ("Nenhum microfone encontrado.", "No microphone found.", "No se encontró ningún micrófono.")
        case .couldNotPlaySound:
            ("Não consegui tocar “%@”.", "Couldn't play “%@”.", "No pude reproducir “%@”.")

        case .newSound: ("Novo som", "New sound", "Nuevo sonido")
        case .editSound: ("Editar som", "Edit sound", "Editar sonido")
        case .fieldName: ("Nome", "Name", "Nombre")
        case .namePlaceholder: ("Ex.: Aplausos", "E.g. Applause", "Ej.: Aplausos")
        case .fieldSound: ("Som", "Sound", "Sonido")
        case .choose: ("Escolher…", "Choose…", "Elegir…")
        case .fieldIcon: ("Ícone", "Icon", "Icono")
        case .emojiOption: ("Emoji", "Emoji", "Emoji")
        case .imageOption: ("Imagem", "Image", "Imagen")
        case .chooseImage: ("Escolher imagem…", "Choose image…", "Elegir imagen…")
        case .change: ("Trocar…", "Change…", "Cambiar…")
        case .fieldVolume: ("Volume", "Volume", "Volumen")
        case .listen: ("Ouvir", "Listen", "Escuchar")
        case .cancel: ("Cancelar", "Cancel", "Cancelar")
        case .save: ("Salvar", "Save", "Guardar")
        case .noFileChosen: ("Nenhum arquivo escolhido", "No file chosen", "Ningún archivo elegido")
        case .keepCurrentSound:
            ("O som atual será mantido", "The current sound will be kept", "Se mantendrá el sonido actual")
        case .chooseSoundPanel:
            (
                "Escolha um som (até %@ segundos)", "Choose a sound (up to %@ seconds)",
                "Elige un sonido (hasta %@ segundos)"
            )
        case .couldNotPlayFile:
            ("Não consegui tocar esse arquivo.", "Couldn't play that file.", "No pude reproducir ese archivo.")

        case .errChooseAudio: ("Escolha um arquivo de áudio.", "Choose an audio file.", "Elige un archivo de audio.")
        case .errImageUnreadable:
            ("Não consegui ler essa imagem.", "Couldn't read that image.", "No pude leer esa imagen.")
        case .errAudioUnreadable:
            (
                "Não consegui ler esse arquivo de áudio.", "Couldn't read that audio file.",
                "No pude leer ese archivo de audio."
            )
        case .errSoundTooLong:
            (
                "O som tem %@ s; o máximo é %@ s.", "The sound is %@ s long; the limit is %@ s.",
                "El sonido dura %@ s; el máximo es %@ s."
            )
        case .errDeviceMissing:
            (
                "O microfone ou o BlackHole não está disponível.", "The microphone or BlackHole is not available.",
                "El micrófono o BlackHole no está disponible."
            )
        case .errStepFailed: ("%@ falhou (erro %@).", "%@ failed (error %@).", "%@ falló (error %@).")
        case .stepCreateAggregate:
            ("Criar o dispositivo agregado", "Creating the aggregate device", "Crear el dispositivo agregado")
        case .stepCreateIOProc: ("Criar o IOProc", "Creating the IOProc", "Crear el IOProc")
        case .stepStartAudio: ("Iniciar o áudio", "Starting the audio", "Iniciar el audio")
        case .errTrimEmpty:
            ("O trecho escolhido está vazio.", "The chosen section is empty.", "El fragmento elegido está vacío.")
        case .errExportFailed:
            (
                "Não consegui exportar a biblioteca.", "Couldn't export the library.",
                "No pude exportar la biblioteca."
            )
        case .errNotALibrary:
            (
                "Esse arquivo não é uma biblioteca do SoundBar.", "That file is not a SoundBar library.",
                "Ese archivo no es una biblioteca de SoundBar."
            )

        case .collapseSection: ("Recolher a seção", "Collapse the section", "Contraer la sección")
        case .expandSection: ("Expandir a seção", "Expand the section", "Expandir la sección")
        case .sectionExpanded: ("Expandida", "Expanded", "Expandida")
        case .sectionCollapsed: ("Recolhida", "Collapsed", "Contraída")
        case .searchSounds: ("Buscar sons", "Search sounds", "Buscar sonidos")
        case .allGroups: ("Todos", "All", "Todos")
        case .masterVolume: ("Volume dos sons", "Sounds volume", "Volumen de los sonidos")
        case .sendToCall: ("Enviar à chamada", "Send to the call", "Enviar a la llamada")
        case .sendToCallHelp:
            (
                "Desligado, só você ouve os sons", "Off, only you hear the sounds",
                "Desactivado, solo tú oyes los sonidos"
            )
        case .muteCall: ("Silenciar a chamada", "Mute the call", "Silenciar la llamada")
        case .unmuteCall: ("Reativar a chamada", "Unmute the call", "Reactivar la llamada")
        case .callMutedStatus:
            (
                "Chamada silenciada: ninguém ouve sua voz nem os sons.",
                "Call muted: nobody hears your voice or the sounds.",
                "Llamada silenciada: nadie oye tu voz ni los sonidos."
            )
        case .moveEarlier: ("Mover para antes", "Move earlier", "Mover antes")
        case .moveLater: ("Mover para depois", "Move later", "Mover después")

        case .libraryMenu: ("Mais opções", "More options", "Más opciones")
        case .exportLibrary: ("Exportar biblioteca…", "Export library…", "Exportar biblioteca…")
        case .importLibrary: ("Importar biblioteca…", "Import library…", "Importar biblioteca…")
        case .importResult:
            (
                "%@ adicionado(s), %@ já existia(m), %@ com erro.", "%@ added, %@ already there, %@ failed.",
                "%@ añadido(s), %@ ya existían, %@ con error."
            )
        case .exportFilePrompt: ("Exportar", "Export", "Exportar")
        case .importFilePrompt: ("Importar", "Import", "Importar")

        case .fieldGroup: ("Grupo", "Group", "Grupo")
        case .groupPlaceholder: ("Sem grupo", "No group", "Sin grupo")
        case .fieldTrim: ("Trecho", "Section", "Fragmento")
        case .trimStart: ("Início", "Start", "Inicio")
        case .trimEnd: ("Fim", "End", "Fin")
        case .secondsValue: ("%@ s", "%@ s", "%@ s")
        case .normalizeVolume: ("Normalizar o volume", "Normalize the volume", "Normalizar el volumen")
        case .normalizeHelp:
            (
                "Deixa este som com um volume parecido com o dos outros",
                "Brings this sound to a volume like the others'",
                "Deja este sonido con un volumen parecido al de los demás"
            )
        case .fieldShortcut: ("Atalho", "Shortcut", "Atajo")
        case .recordShortcut: ("Gravar atalho", "Record shortcut", "Grabar atajo")
        case .pressShortcut: ("Pressione o atalho…", "Press the shortcut…", "Pulsa el atajo…")
        case .clearShortcut: ("Limpar", "Clear", "Borrar")
        case .noShortcut: ("Nenhum", "None", "Ninguno")

        case .shortcutsMenu: ("Atalhos…", "Shortcuts…", "Atajos…")
        case .shortcutsTitle: ("Atalhos", "Shortcuts", "Atajos")
        case .shortcutsHelp:
            (
                "Funcionam em qualquer app, com o SoundBar em segundo plano. Cada som tem o seu no editor.",
                "They work in any app, with SoundBar in the background. Each sound has its own in the editor.",
                "Funcionan en cualquier app, con SoundBar en segundo plano. Cada sonido tiene el suyo en el editor."
            )
        case .actionStopAll: ("Parar todos os sons", "Stop all sounds", "Detener todos los sonidos")
        case .actionCallMute: ("Silenciar a chamada", "Mute the call", "Silenciar la llamada")
        case .actionMicMute: ("Silenciar o microfone", "Mute the microphone", "Silenciar el micrófono")
        case .shortcutNeedsModifier:
            (
                "Use pelo menos ⌃, ⌥ ou ⌘ junto com a tecla.", "Use at least ⌃, ⌥ or ⌘ with the key.",
                "Usa al menos ⌃, ⌥ o ⌘ junto con la tecla."
            )
        case .shortcutInUse:
            (
                "Esse atalho já é usado por “%@”.", "That shortcut is already used by “%@”.",
                "Ese atajo ya lo usa “%@”."
            )
        case .shortcutUnavailable:
            (
                "Outro app já usa esse atalho.", "Another app already uses that shortcut.",
                "Otra app ya usa ese atajo."
            )
        }
    }

    func text(in language: ResolvedLanguage) -> String {
        switch language {
        case .pt: translations.pt
        case .en: translations.en
        case .es: translations.es
        }
    }

    /// The text in the language the app is in now.
    var string: String { text(in: Language.current) }

    /// The text in the language the app is in now, with `arguments` in place of the `%@`, in order.
    func formatted(_ arguments: String...) -> String {
        Self.fill(text(in: Language.current), with: arguments)
    }

    /// The text in `language`, with `arguments` in place of the `%@`, in order.
    func formatted(in language: ResolvedLanguage, _ arguments: String...) -> String {
        Self.fill(text(in: language), with: arguments)
    }

    private static func fill(_ template: String, with arguments: [String]) -> String {
        var result = ""
        var remaining = arguments[...]
        var rest = template[...]
        while let range = rest.range(of: "%@") {
            result += rest[..<range.lowerBound]
            result += remaining.popFirst() ?? ""
            rest = rest[range.upperBound...]
        }
        return result + rest
    }
}
