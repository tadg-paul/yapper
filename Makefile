# ABOUTME: Build, test, install, and release targets for yapper.
# ABOUTME: Standard entry points per project conventions.

# xcodebuild is required (not swift build) because MLX Swift needs
# Metal shader compilation, which only Xcode's build system supports.

.PHONY: build test test-framework test-cli test-audio test-all test-one-off lint install uninstall clean help release release-models sync

SCHEME := yapper-Package
DESTINATION := platform=OS X
INSTALL_DIR := $(HOME)/.local/bin
DERIVED_DATA := $(HOME)/Library/Developer/Xcode/DerivedData

build: ## Build the project
	xcodebuild build -scheme yapper -destination '$(DESTINATION)' -quiet
	@# Copy MisakiSwift resource bundle into its framework (needed for CLI and tests)
	@cp -R $(DERIVED_DATA)/yapper-*/Build/Products/Debug/MisakiSwift_MisakiSwift.bundle \
		$(DERIVED_DATA)/yapper-*/Build/Products/Debug/PackageFrameworks/MisakiSwift.framework/Versions/A/Resources/ \
		2>/dev/null || true

lint: ## Run linter
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint lint --quiet; \
	else \
		echo "swiftlint not found, skipping lint"; \
	fi

test: test-framework test-cli ## Run release-safe regression tests

test-framework: lint ## Run framework tests only
	@xcodebuild build-for-testing -scheme $(SCHEME) -destination '$(DESTINATION)' -quiet
	@cp -R $(DERIVED_DATA)/yapper-*/Build/Products/Debug/MisakiSwift_MisakiSwift.bundle \
		$(DERIVED_DATA)/yapper-*/Build/Products/Debug/PackageFrameworks/MisakiSwift.framework/Versions/A/Resources/ \
		2>/dev/null || true
	@xcodebuild test-without-building -scheme $(SCHEME) -destination '$(DESTINATION)' \
		-only-testing:YapperKitTests \
		-parallel-testing-enabled NO \
		-skip-testing:YapperKitTests/SpeakCommandTests \
		-skip-testing:YapperKitTests/VoicesCommandTests \
		-skip-testing:YapperKitTests/ConvertCommandTests \
		-skip-testing:YapperKitTests/VoiceSelectionPrecedenceTests \
		-skip-testing:YapperKitTests/YapShortcutTests \
		2>&1 | \
		grep -v "^objc\[" | \
		grep -v "duplicates must be" | \
		grep -v "may cause spurious" | \
		grep -v "^$$"

test-cli: build ## Run release-safe CLI command tests
	@bash Tests/regression/cli/test_release_cli.sh

test-audio: build ## Run audio/playback CLI regression tests
	@bash Tests/regression/cli/test_speak.sh
	@bash Tests/regression/cli/test_voices.sh
	@bash Tests/regression/cli/test_convert.sh
	@bash Tests/regression/cli/test_convert_delta.sh
	@bash Tests/regression/cli/test_progress.sh
	@bash Tests/regression/cli/test_script.sh
	@bash Tests/regression/cli/test_concurrent_convert.sh
	@bash Tests/regression/cli/test_preamble.sh
	@bash Tests/regression/cli/test_fountain.sh
	@bash Tests/regression/cli/test_pronunciation.sh
	@bash Tests/regression/cli/test_yap.sh

test-all: test-framework test-cli test-audio ## Run release-safe and audio regression tests

test-one-off: lint ## Run one-off tests (not part of regression)
	@xcodebuild build-for-testing -scheme $(SCHEME) -destination '$(DESTINATION)' -quiet
	@cp -R $(DERIVED_DATA)/yapper-*/Build/Products/Debug/MisakiSwift_MisakiSwift.bundle \
		$(DERIVED_DATA)/yapper-*/Build/Products/Debug/PackageFrameworks/MisakiSwift.framework/Versions/A/Resources/ \
		2>/dev/null || true
	@xcodebuild test-without-building -scheme $(SCHEME) -destination '$(DESTINATION)' \
		-only-testing:YapperOneOffTests \
		-parallel-testing-enabled NO \
		2>&1 | \
		grep -v "^objc\[" | \
		grep -v "duplicates must be" | \
		grep -v "may cause spurious" | \
		grep -v "^$$"

install: build ## Install yapper (and yap shortcut) to ~/.local/bin
	$(eval PRODDIR := $(shell find $(DERIVED_DATA)/yapper-*/Build/Products/Debug -name yapper -type f 2>/dev/null | head -1 | xargs dirname))
	@if [ -z "$(PRODDIR)" ]; then \
		echo "Error: could not find yapper binary. Run 'make build' first."; \
		exit 1; \
	fi
	@mkdir -p "$(INSTALL_DIR)"
	@# Wrapper scripts, NOT symlinks. macOS's _NSGetExecutablePath (and therefore
	@# Bundle.main.bundleURL) resolves to the caller's invocation path, not through
	@# symlinks — so a symlink at $(INSTALL_DIR)/yapper would cause MLX to look for
	@# mlx-swift_Cmlx.bundle in $(INSTALL_DIR)/ instead of the DerivedData directory
	@# where the .bundle resources live, and synthesis would fail at runtime.
	@# `exec` ensures the parent shell is replaced so signals and exit codes pass
	@# through cleanly. `exec -a yap` sets argv[0]="yap" for the yap wrapper so
	@# the binary's own argv[0] dispatch routes to the speak subcommand.
	@# Remove any existing file or symlink at the target paths before writing.
	@rm -f "$(INSTALL_DIR)/yapper" "$(INSTALL_DIR)/yap"
	@printf '#!/bin/bash\nexport LLVM_PROFILE_FILE=/dev/null\nexec "%s/yapper" "$$@"\n' "$(PRODDIR)" > "$(INSTALL_DIR)/yapper"
	@printf '#!/bin/bash\nexport LLVM_PROFILE_FILE=/dev/null\nexec -a yap "%s/yapper" "$$@"\n' "$(PRODDIR)" > "$(INSTALL_DIR)/yap"
	@chmod +x "$(INSTALL_DIR)/yapper" "$(INSTALL_DIR)/yap"
	@echo "Installed yapper and yap to $(INSTALL_DIR)"

uninstall: ## Remove yapper and yap from ~/.local/bin
	@rm -f "$(INSTALL_DIR)/yapper" "$(INSTALL_DIR)/yap"
	@echo "Removed yapper and yap from $(INSTALL_DIR)"

clean: ## Remove build artefacts
	swift package clean
	@xcodebuild clean -scheme $(SCHEME) -destination '$(DESTINATION)' -quiet 2>/dev/null || true

sync: ## Git sync: add, commit, pull, push (submodules first if present)
	@if [ -f .gitmodules ]; then \
		git submodule foreach 'git add --all && git diff --cached --quiet || git commit -m "sync: $$(basename $$PWD)" && git pull && git push'; \
	fi
	@git add --all
	@if ! git diff --cached --quiet; then \
		git commit -m "sync"; \
	else \
		echo "Nothing to commit"; \
	fi
	@git pull
	@git push

release-models: ## Package and upload model weights + English voices to models-v1 release
	@bash scripts/release-models.sh

release: ## Bump version, tag, push, update Homebrew formula (usage: make release [VERSION])
ifndef SKIP_TESTS
	@$(MAKE) test
endif
	@SKIP_TESTS="$(SKIP_TESTS)" bash scripts/release.sh $(VERSION)

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'
