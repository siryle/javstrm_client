#!/usr/bin/env python3
"""Generate the Xcode project with Python's standard library only."""
from pathlib import Path
import hashlib
import json
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "JavStrm.xcodeproj"


def ident(value):
    return hashlib.sha1(value.encode()).hexdigest()[:24].upper()


def quote(value):
    return json.dumps(str(value), ensure_ascii=True)


def generate():
    PROJECT.mkdir(exist_ok=True)
    objects = {}

    def add(name, content):
        key = ident(name)
        objects[key] = content
        return key

    sources = sorted((ROOT / "JavStrm").rglob("*.swift"))
    resources = [
        ROOT / "JavStrm/Resources/Assets.xcassets",
        ROOT / "JavStrm/Resources/PrivacyInfo.xcprivacy",
    ]
    source_builds, resource_builds, files = [], [], []
    for path in sources + resources + [ROOT / "JavStrm/Resources/Info.plist"]:
        relative = path.relative_to(ROOT).as_posix()
        kind = (
            "sourcecode.swift" if path.suffix == ".swift" else
            "folder.assetcatalog" if path.suffix == ".xcassets" else "text.xml"
        )
        ref = add(relative, f"{{isa = PBXFileReference; lastKnownFileType = {kind}; path = {quote(relative)}; sourceTree = SOURCE_ROOT; }}")
        files.append(ref)
        if path in sources or path in resources:
            build = add("build:" + relative, f"{{isa = PBXBuildFile; fileRef = {ref}; }}")
            (source_builds if path in sources else resource_builds).append(build)

    product = add("product", "{isa = PBXFileReference; explicitFileType = wrapper.application; path = JavStrm.app; sourceTree = BUILT_PRODUCTS_DIR; }")
    package = add("package", '{isa = XCLocalSwiftPackageReference; relativePath = "."; }')
    package_product = add("package-product", f"{{isa = XCSwiftPackageProductDependency; package = {package}; productName = JavStrmCore; }}")
    package_build = add("package-build", f"{{isa = PBXBuildFile; productRef = {package_product}; }}")
    main_group = add("main-group", f"{{isa = PBXGroup; children = ({','.join(files)},{ident('products')},); sourceTree = \"<group>\"; }}")
    products = add("products", f"{{isa = PBXGroup; children = ({product},); name = Products; sourceTree = \"<group>\"; }}")
    source_phase = add("sources", f"{{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({','.join(source_builds)},); runOnlyForDeploymentPostprocessing = 0; }}")
    resource_phase = add("resources", f"{{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({','.join(resource_builds)},); runOnlyForDeploymentPostprocessing = 0; }}")
    framework_phase = add("frameworks", f"{{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({package_build},); runOnlyForDeploymentPostprocessing = 0; }}")

    project_configs, target_configs = [], []
    for name in ["Debug", "Release"]:
        settings = {
            "ALWAYS_SEARCH_USER_PATHS": "NO",
            "CLANG_ENABLE_MODULES": "YES",
            "CLANG_ENABLE_OBJC_ARC": "YES",
            "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
            "SDKROOT": "iphoneos",
            "SWIFT_VERSION": "6.0",
            "SWIFT_STRICT_CONCURRENCY": "complete",
        }
        if name == "Debug":
            settings.update({"DEBUG_INFORMATION_FORMAT": "dwarf", "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
                             "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG", "ENABLE_TESTABILITY": "YES"})
        else:
            settings.update({"DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
                             "SWIFT_COMPILATION_MODE": "wholemodule", "SWIFT_OPTIMIZATION_LEVEL": "-O"})
        serialized = " ".join(f"{key} = {quote(value)};" for key, value in settings.items())
        project_configs.append(add("project-" + name, f"{{isa = XCBuildConfiguration; buildSettings = {{{serialized}}}; name = {name}; }}"))
        settings = {
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
            "CODE_SIGN_STYLE": "Automatic",
            "CURRENT_PROJECT_VERSION": "1",
            "GENERATE_INFOPLIST_FILE": "NO",
            "INFOPLIST_FILE": "JavStrm/Resources/Info.plist",
            "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
            "MARKETING_VERSION": "1.1.0",
            "PRODUCT_BUNDLE_IDENTIFIER": "com.sean.javstrm",
            "PRODUCT_NAME": "$(TARGET_NAME)",
            "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
            "SUPPORTS_MACCATALYST": "NO",
            "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
            "TARGETED_DEVICE_FAMILY": "1,2",
            "SWIFT_EMIT_LOC_STRINGS": "YES",
        }
        serialized = " ".join(f"{key} = {quote(value)};" for key, value in settings.items())
        target_configs.append(add("target-" + name, f"{{isa = XCBuildConfiguration; buildSettings = {{{serialized}}}; name = {name}; }}"))

    project_list = add("project-configs", f"{{isa = XCConfigurationList; buildConfigurations = ({','.join(project_configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }}")
    target_list = add("target-configs", f"{{isa = XCConfigurationList; buildConfigurations = ({','.join(target_configs)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }}")
    target = add("target", f"{{isa = PBXNativeTarget; buildConfigurationList = {target_list}; buildPhases = ({source_phase},{framework_phase},{resource_phase},); buildRules = (); dependencies = (); name = JavStrm; packageProductDependencies = ({package_product},); productName = JavStrm; productReference = {product}; productType = \"com.apple.product-type.application\"; }}")
    project = add("project", f"""{{isa = PBXProject;
        attributes = {{BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600;
            TargetAttributes = {{{target} = {{CreatedOnToolsVersion = 16.0; }}; }}; }};
        buildConfigurationList = {project_list};
        compatibilityVersion = "Xcode 14.0";
        developmentRegion = "zh-Hans";
        hasScannedForEncodings = 0;
        knownRegions = ("zh-Hans", en, Base,);
        mainGroup = {main_group};
        packageReferences = ({package},);
        productRefGroup = {products};
        projectDirPath = "";
        projectRoot = "";
        targets = ({target},);
    }}""")
    content = "// !$*UTF8*$!\n{\narchiveVersion = 1;\nclasses = {};\nobjectVersion = 56;\nobjects = {\n"
    content += "".join(f"{key} = {value};\n" for key, value in sorted(objects.items()))
    content += f"}};\nrootObject = {project};\n}}\n"
    (PROJECT / "project.pbxproj").write_text(content)

    scheme_dir = PROJECT / "xcshareddata/xcschemes"
    scheme_dir.mkdir(parents=True, exist_ok=True)
    scheme = ET.Element("Scheme", LastUpgradeVersion="1600", version="1.3")
    build = ET.SubElement(scheme, "BuildAction", parallelizeBuildables="YES", buildImplicitDependencies="YES")
    entries = ET.SubElement(build, "BuildActionEntries")
    entry = ET.SubElement(entries, "BuildActionEntry", **{
        "buildForTesting": "YES", "buildForRunning": "YES", "buildForProfiling": "YES",
        "buildForArchiving": "YES", "buildForAnalyzing": "YES",
    })

    def reference(parent):
        ET.SubElement(parent, "BuildableReference", BuildableIdentifier="primary", BlueprintIdentifier=target,
                      BuildableName="JavStrm.app", BlueprintName="JavStrm",
                      ReferencedContainer="container:JavStrm.xcodeproj")

    reference(entry)
    ET.SubElement(scheme, "TestAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB",
                  selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", shouldUseLaunchSchemeArgsEnv="YES")
    launch = ET.SubElement(scheme, "LaunchAction", buildConfiguration="Debug",
                          selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB",
                          selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB",
                          launchStyle="0", useCustomWorkingDirectory="NO", ignoresPersistentStateOnLaunch="NO",
                          debugDocumentVersioning="YES", debugServiceExtension="internal", allowLocationSimulation="YES")
    reference(ET.SubElement(launch, "BuildableProductRunnable", runnableDebuggingMode="0"))
    profile = ET.SubElement(scheme, "ProfileAction", buildConfiguration="Release", shouldUseLaunchSchemeArgsEnv="YES",
                            savedToolIdentifier="", useCustomWorkingDirectory="NO", debugDocumentVersioning="YES")
    reference(ET.SubElement(profile, "BuildableProductRunnable", runnableDebuggingMode="0"))
    ET.SubElement(scheme, "AnalyzeAction", buildConfiguration="Debug")
    ET.SubElement(scheme, "ArchiveAction", buildConfiguration="Release", revealArchiveInOrganizer="YES")
    ET.indent(scheme)
    ET.ElementTree(scheme).write(scheme_dir / "JavStrm.xcscheme", encoding="utf-8", xml_declaration=True)
    workspace = PROJECT / "project.xcworkspace"
    workspace.mkdir(exist_ok=True)
    (workspace / "contents.xcworkspacedata").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n<Workspace version="1.0"><FileRef location="self:"/></Workspace>\n'
    )
    print(f"Generated JavStrm.xcodeproj: {len(sources)} Swift files, local JavStrmCore package.")


if __name__ == "__main__":
    generate()
