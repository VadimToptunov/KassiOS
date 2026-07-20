# Generates KassIntegration.xcodeproj: a SwiftUI demo app + a UI-test target that
# compiles the KassiOS sources directly and runs the demo UI tests.
# Run from the IntegrationTests directory: `ruby gen.rb`.
require "xcodeproj"

PROJECT = "KassIntegration.xcodeproj"
project = Xcodeproj::Project.new(PROJECT)

def add(project, target, glob)
  refs = Dir.glob(glob).sort.map { |path| project.main_group.new_file(path) }
  target.add_file_references(refs)
end

# --- App target -------------------------------------------------------------
app = project.new_target(:application, "KassDemo", :ios, "16.0")
add(project, app, "DemoApp/*.swift")
app.build_configurations.each do |c|
  s = c.build_settings
  s["PRODUCT_BUNDLE_IDENTIFIER"] = "com.kassios.KassDemo"
  s["GENERATE_INFOPLIST_FILE"] = "YES"
  s["INFOPLIST_KEY_UILaunchScreen_Generation"] = "YES"
  # Lets the demo raise a real location system dialog (for SystemAlertInterceptor).
  s["INFOPLIST_KEY_NSLocationWhenInUseUsageDescription"] = "Demo location permission for KassiOS system-alert tests."
  s["SWIFT_VERSION"] = "5.0"
  s["IPHONEOS_DEPLOYMENT_TARGET"] = "16.0"
  s["TARGETED_DEVICE_FAMILY"] = "1,2"
  s["MARKETING_VERSION"] = "1.0"
  s["CURRENT_PROJECT_VERSION"] = "1"
  s["CODE_SIGNING_ALLOWED"] = "NO"
end

# --- UI-test target ---------------------------------------------------------
uitests = project.new_target(:ui_test_bundle, "KassDemoUITests", :ios, "16.0")
add(project, uitests, "../Sources/KassiOS/*.swift")   # compile the library directly
add(project, uitests, "UITests/*.swift")
uitests.build_configurations.each do |c|
  s = c.build_settings
  s["PRODUCT_BUNDLE_IDENTIFIER"] = "com.kassios.KassDemoUITests"
  s["TEST_TARGET_NAME"] = "KassDemo"
  s["GENERATE_INFOPLIST_FILE"] = "YES"
  s["SWIFT_VERSION"] = "5.0"
  s["IPHONEOS_DEPLOYMENT_TARGET"] = "16.0"
  s["TARGETED_DEVICE_FAMILY"] = "1,2"
  s["CODE_SIGNING_ALLOWED"] = "NO"
end
uitests.add_dependency(app)

project.save

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app)
scheme.add_build_target(uitests)
scheme.add_test_target(uitests)
scheme.set_launch_target(app)
scheme.save_as(PROJECT, "KassDemoUITests", true)

puts "Generated #{PROJECT} (KassDemo app + KassDemoUITests)"
