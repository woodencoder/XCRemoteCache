# encoding: utf-8
require 'open-uri'
require 'shellwords'

################################
# Rake configuration
################################

# Make sure environment is UTF-8 (CI sometimes thinks it's ASCII)
ENV['LANG'] = 'en_US.UTF-8'
ENV['LANGUAGE'] = 'en_US.UTF-8'
ENV['LC_ALL'] = 'en_US.UTF-8'
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

# Environment variables (you can override those by adding parameters
# to task definitions in buildconf/tasks)
CONFIG = ENV['CONFIG'] || 'debug'
CI = !!ENV['TEAMCITY_VERSION']
GIT_REF = ENV['GITHUB_REF']

# Paths
DERIVED_DATA_DIR = File.join('.build').freeze
RELEASES_ROOT_DIR = File.join('releases').freeze

EXECUTABLE_NAME = 'XCRemoteCache'
EXECUTABLE_NAMES = ['xclibtool', 'xcpostbuild', 'xcprebuild', 'xcprepare', 'xcswiftc', 'xcld'] 
SCHEME = 'XCRemoteCacheApp'
TEST_SCHEME = 'XCRemoteCacheTests'
PROJECT_NAME = 'XCRemoteCache'

SWIFTLINT_ENABLED = true
SWIFTFORMAT_ENABLED = true

################################
# Tasks
################################

task :prepare do
  Dir.mkdir(DERIVED_DATA_DIR) unless File.exists?(DERIVED_DATA_DIR)
end

desc 'lint'
task :lint => [:prepare] do
  puts 'Run linting'

  system("swiftformat --lint --config .swiftformat --cache ignore .") or abort "swiftformat failure" if SWIFTFORMAT_ENABLED
  system("swiftlint lint --config .swiftlint.yml") or abort "swiftlint failure" if SWIFTLINT_ENABLED
end

task :autocorrect => [:prepare]  do 
  puts 'Run autocorrect'

  system("swiftformat --config .swiftformat --cache ignore .") or abort "swiftformat failure" if SWIFTFORMAT_ENABLED
  system("swiftlint autocorrect --config .swiftlint.yml") or abort "swiftlint failure" if SWIFTLINT_ENABLED
end

desc 'build package artifacts'
task :build, [:configuration, :sdks] do |task, args|
  # Set task defaults
  args.with_defaults(:configuration => CONFIG.downcase, :sdks => ['macos'])

  unless args.configuration == 'Debug'.downcase || args.configuration == 'Release'.downcase
    fail("Unsupported configuration. Valid values: ['Debug', 'Release']. Found '#{args.configuration}''")
  end

  # Clean data generated by SPM
  # FIXME: dangerous recursive rm
  system("rm -rf #{DERIVED_DATA_DIR} > /dev/null 2>&1")

  # Build
  build_paths = []
  args.sdks.each do |sdk|
    spm_build(args.configuration)

    # Path of the executable looks like: `.build/(debug|release)/XCRemoteCache`
    build_path_base = File.join(DERIVED_DATA_DIR, args.configuration)
    sdk_build_paths = EXECUTABLE_NAMES.map {|e| File.join(build_path_base, e)}

    build_paths.push(sdk_build_paths)
  end

  puts "Build products: #{build_paths}"

  if args.configuration == 'Release'.downcase
    puts "Creating release zip"
    package = create_release_zip(build_paths[0])
  end
end

desc 'run tests with SPM'
task :test do
  # Running tests
  spm_test()
end

################################
# Helper functions
################################

def spm_build(configuration)
  spm_cmd = "swift build "\
              "-c #{configuration}"
  system(spm_cmd) or abort "Build failure"
end

def bash(command)
  escaped_command = Shellwords.escape(command)
  system "bash -c #{escaped_command}"
end

def spm_test()
  tests_output_file = File.join(DERIVED_DATA_DIR, 'tests.log')
  # Redirect error stream with to a file and pass to the second stream output 
  spm_cmd = "swift test --enable-code-coverage 2> >(tee #{tests_output_file})"
  test_succeeded = bash(spm_cmd)
  
  abort "Test failure" unless test_succeeded
end

def create_release_zip(build_paths)
  release_dir = RELEASES_ROOT_DIR
  output_artifact_basename = "#{PROJECT_NAME}.zip"
  library_file = File.join(release_dir, output_artifact_basename)

  # Create and move files into the release directory
  mkdir_p release_dir
  build_paths.each {|p|
    cp_r p, release_dir
  }

  Dir.chdir(release_dir) do
    # -X: no extras (uid, gid, file times, ...)
    # -r: recursive
    system("zip -X -r #{output_artifact_basename} .") or abort "zip failure"
    # List contents of zip file
    system("unzip -l #{output_artifact_basename}") or abort "unzip failure"
  end
  library_file
end
