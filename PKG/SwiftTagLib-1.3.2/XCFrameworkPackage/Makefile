
xcframework:
	@command -v swift-create-xcframework >/dev/null 2>&1 || { echo "please install https://github.com/segment-integrations/swift-create-xcframework"; exit 1; }
	@command -v xcbeautify >/dev/null 2>&1 || { echo "please install https://github.com/cpisciotta/xcbeautify"; exit 1; }
	@rm -rf .build
	@rm -rf SwiftTagLib.xcframework SwiftTagLib.zip SwiftTagLib.sha256
	@rm -rf CxxTagLibBridge.xcframework CxxTagLibBridge.zip CxxTagLibBridge.sha256
	@rm -rf taglib.xcframework taglib.zip taglib.sha256
	@rm -rf Package.resolved
	time swift-create-xcframework \
		--platform ios \
		--xcconfig xcframework.xcconfig \
		--xc-setting BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
		--no-debug-symbols \
		| xcbeautify -q

# should include DSYM, can toggle between --debug-symbols and --no-debug-sybmols
# not including DSYM saves about 80% of the size of XCFramework
# if macos is needed add --platform macos
# add --zip if distribution as package is needed
