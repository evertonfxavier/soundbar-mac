# One entry point for the two halves of the project: the macOS app (Swift, built with swiftc) and the Chrome
# extension (TypeScript, in ChromeExtension/). `make` lists the targets.

.DEFAULT_GOAL := help
.PHONY: help app run test test-app test-extension compile-app lint format check dmg extension zip icons clean

help: ## list the targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{ printf "  make %-15s %s\n", $$1, $$2 }'

# ---------- the macOS app ----------

app: ## build build/SoundBar.app
	scripts/build-app.sh

run: ## build and (re)open the app
	scripts/build-app.sh --run

dmg: app ## build the disk image, build/SoundBar-v<version>.dmg
	scripts/make-dmg.sh

# ---------- the Chrome extension ----------

extension: ## build ChromeExtension/dist (load it in chrome://extensions)
	cd ChromeExtension && pnpm install --frozen-lockfile && pnpm build

zip: ## build the extension and zip it into build/SoundBar-Bridge-v<version>.zip
	cd ChromeExtension && pnpm install --frozen-lockfile && pnpm package

# ---------- checks ----------

test: test-app test-extension ## run every test

test-app: ## the Swift tests (Swift Testing, compiled with swiftc), warnings are errors
	SWIFTFLAGS=-warnings-as-errors scripts/test.sh

test-extension: ## the extension's tests, with coverage
	cd ChromeExtension && pnpm install --frozen-lockfile && pnpm test:coverage

lint: ## everything the pipeline checks before it tests
	swift format lint --strict --configuration .swift-format --recursive Sources Tests
	cd ChromeExtension && pnpm install --frozen-lockfile && pnpm lint && pnpm typecheck && pnpm format:check
	node --test scripts/release.test.mjs

format: ## format the Swift sources and the extension
	swift format --in-place --configuration .swift-format --recursive Sources Tests
	cd ChromeExtension && pnpm format

compile-app: ## compile the whole app, views included, with warnings as errors (into build/check, not build/)
	OUT_DIR=build/check SWIFTFLAGS=-warnings-as-errors scripts/build-app.sh

check: lint test compile-app ## lint, test and compile the app, as the pipeline does

# ---------- other ----------

icons: ## render the icons again from assets/*.svg (needs librsvg: brew install librsvg)
	scripts/make-icons.sh

clean: ## remove what the builds made
	rm -rf build ChromeExtension/dist ChromeExtension/coverage
