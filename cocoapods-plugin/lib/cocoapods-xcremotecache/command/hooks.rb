# Copyright 2021 Spotify AB
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'cocoapods'
require 'cocoapods/resolver'
require 'open-uri'
require 'yaml'
require 'json'


module CocoapodsXCRemoteCacheModifier
  # Registers for CocoaPods plugin hooks
  module Hooks
    BIN_DIR = '.rc'
    FAKE_SRCROOT = "/#{'x' * 10 }"
    LLDB_INIT_COMMENT="#RemoteCacheCustomSourceMap"
    LLDB_INIT_PATH = "#{ENV['HOME']}/.lldbinit"
    FAT_ARCHIVE_NAME_INFIX = 'arm64-x86_64'

    CUSTOM_CONFIGURATION_KEYS = [
      'enabled', 
      'xcrc_location',
      'exclude_targets',
      'exclude_build_configurations',
      'final_target',
      'check_build_configuration', 
      'check_platform', 
      'modify_lldb_init'
    ]

    class XCRemoteCache
      @@configuration = nil

      def self.configure(c) 
        @@configuration = c
      end

      def self.set_configuration_default_values
        default_values = {
          'mode' => 'consumer',
          'enabled' => true, 
          'xcrc_location' => "XCRC",
          'exclude_build_configurations' => [],
          'check_build_configuration' => 'Debug',
          'check_platform' => 'iphonesimulator', 
          'modify_lldb_init' => true, 
          'xccc_file' => "#{BIN_DIR}/xccc",
          'remote_commit_file' => "#{BIN_DIR}/arc.rc",
          'exclude_targets' => [],
        }
        @@configuration.merge! default_values.select { |k, v| !@@configuration.key?(k) }
      end

      def self.validate_configuration()
        required_values = [
          'cache_addresses', 
          'primary_repo',
          'check_build_configuration',
          'check_platform'
        ]
        
        missing_configuration_values = required_values.select { |v| !@@configuration.key?(v) }
        unless missing_configuration_values.empty?
          throw "XCRemoteCache not fully configured. Make sure all required fields are provided. Missing fields are: #{missing_configuration_values.join(', ')}."
        end

        mode = @@configuration['mode']
        unless mode == 'consumer' || mode == 'producer'
          throw "Incorrect 'mode' value. Allowed values are ['consumer', 'producer'], but you provided '#{mode}'. A typo?"
        end

        unless mode == 'consumer' || @@configuration.key?('final_target')
          throw "Missing 'final_target' value in the Pod configuration."
        end
      end

      def self.generate_rcinfo()
        @@configuration.select { |key, value| !CUSTOM_CONFIGURATION_KEYS.include?(key) }
      end

      def self.enable_xcremotecache(target, xc_location, xc_cc_path, mode, exclude_build_configurations, final_target)
        target.build_configurations.each do |config|
          # apply only for relevant Configurations
          next if exclude_build_configurations.include?(config.name)
          if mode == 'consumer'
            config.build_settings['CC'] = ["$SRCROOT/#{xc_cc_path}"]
          end
          config.build_settings['SWIFT_EXEC'] = ["$SRCROOT/#{xc_location}/xcswiftc"]
          config.build_settings['LIBTOOL'] = ["$SRCROOT/#{xc_location}/xclibtool"]
          config.build_settings['LD'] = ["$SRCROOT/#{xc_location}/xcld"]

          config.build_settings['XCREMOTE_CACHE_FAKE_SRCROOT'] = FAKE_SRCROOT
          add_cflags!(config.build_settings, '-fdebug-prefix-map', "$(SRCROOT:dir:standardizepath)=$(XCREMOTE_CACHE_FAKE_SRCROOT)")
          add_swiftflags!(config.build_settings, '-debug-prefix-map', "$(SRCROOT:dir:standardizepath)=$(XCREMOTE_CACHE_FAKE_SRCROOT)")
        end

        # Prebuild
        if mode == 'consumer'
          existing_prebuild_script = target.build_phases.detect do |phase|
            if phase.respond_to?(:name)
              phase.name != nil && phase.name.start_with?("[XCRC] Prebuild")
            end
          end
          prebuild_script = existing_prebuild_script || target.new_shell_script_build_phase("[XCRC] Prebuild")
          prebuild_script.shell_script = "\"$SCRIPT_INPUT_FILE_0\""
          prebuild_script.input_paths = ["$SRCROOT/#{xc_location}/xcprebuild"]
          prebuild_script.output_paths = [
            "$(TARGET_TEMP_DIR)/rc.enabled",
            "$(DWARF_DSYM_FOLDER_PATH)/$(DWARF_DSYM_FILE_NAME)"
          ]
          prebuild_script.dependency_file = "$(TARGET_TEMP_DIR)/prebuild.d"

          # Move prebuild (last element) to the first position (to make it real 'prebuild')
          target.build_phases.rotate!(-1) if existing_prebuild_script.nil?
        elsif mode == 'producer'
          # Delete existing prebuild build phase (to support switching between modes)
          target.build_phases.delete_if do |phase|
            if phase.respond_to?(:name)
              phase.name != nil && phase.name.start_with?("[XCRC] Prebuild")
            end
          end
        end

        # Postbuild
        existing_postbuild_script = target.build_phases.detect do |phase|
          if phase.respond_to?(:name)
            phase.name != nil && phase.name.start_with?("[XCRC] Postbuild")
          end
        end
        postbuild_script = existing_postbuild_script || target.new_shell_script_build_phase("[XCRC] Postbuild")
        postbuild_script.shell_script = "\"$SCRIPT_INPUT_FILE_0\""
        postbuild_script.input_paths = ["$SRCROOT/#{xc_location}/xcpostbuild"]
        postbuild_script.output_paths = [
          "$(TARGET_BUILD_DIR)/$(MODULES_FOLDER_PATH)/$(PRODUCT_MODULE_NAME).swiftmodule/$(PLATFORM_PREFERRED_ARCH).swiftmodule.md5",
          "$(TARGET_BUILD_DIR)/$(MODULES_FOLDER_PATH)/$(PRODUCT_MODULE_NAME).swiftmodule/$(PLATFORM_PREFERRED_ARCH)-$(LLVM_TARGET_TRIPLE_VENDOR)-$(SWIFT_PLATFORM_TARGET_PREFIX)$(LLVM_TARGET_TRIPLE_SUFFIX).swiftmodule.md5"
        ]
        postbuild_script.dependency_file = "$(TARGET_TEMP_DIR)/postbuild.d"

        # Mark a sha as ready for a given platform and configuration when building the final_target
        if mode == 'producer' && target.name == final_target
          existing_mark_script = target.build_phases.detect do |phase|
            if phase.respond_to?(:name)
              phase.name != nil && phase.name.start_with?("[XCRC] Mark")
            end
          end
          mark_script = existing_mark_script || target.new_shell_script_build_phase("[XCRC] Mark")
          mark_script.shell_script = "\"$SCRIPT_INPUT_FILE_0\" mark --configuration $CONFIGURATION --platform $PLATFORM_NAME"
          mark_script.input_paths = ["$SRCROOT/#{xc_location}/xcprepare"]
        else
          # Delete existing mark build phase (to support switching between modes or changing the final target)
          target.build_phases.delete_if do |phase|
            if phase.respond_to?(:name)
              phase.name != nil && phase.name.start_with?("[XCRC] Mark")
            end
          end
        end
      end

      def self.disable_xcremotecache_for_target(target)
        target.build_configurations.each do |config|
          config.build_settings.delete('CC') if config.build_settings.key?('CC')
          config.build_settings.delete('SWIFT_EXEC') if config.build_settings.key?('SWIFT_EXEC')
          config.build_settings.delete('LIBTOOL') if config.build_settings.key?('LIBTOOL')
          config.build_settings.delete('LD') if config.build_settings.key?('LD')
          # Add Fake src root for ObjC & Swift
          config.build_settings.delete('XCREMOTE_CACHE_FAKE_SRCROOT')
          remove_cflags!(config.build_settings, '-fdebug-prefix-map')
          remove_swiftflags!(config.build_settings, '-debug-prefix-map')
        end

        # User project is not generated from scratch (contrary to `Pods`), delete all previous XCRemoteCache phases
        target.build_phases.delete_if {|phase| 
          # Some phases (e.g. PBXSourcesBuildPhase) don't have strict name check respond_to?
          if phase.respond_to?(:name) 
              phase.name != nil && phase.name.start_with?("[XCRC]")
          end
        }
      end

      # Writes XCRemoteCache info in the specified directory location
      def self.save_rcinfo(info, directory)
          File.open(File.join(directory, '.rcinfo'), 'w') { |file| file.write info.to_yaml }
      end

      def self.download_xcrc_if_needed(local_location)
        required_binaries = ['xcld', 'xclibtool', 'xcpostbuild', 'xcprebuild', 'xcprepare', 'xcswiftc']
        binaries_exist = required_binaries.reduce(true) do |exists, filename|
          file_path = File.join(local_location, filename) 
          exists = exists && File.exist?(file_path)
        end

        # Don't download XCRemoteCache if provided directory already contains it
        return if binaries_exist

        Dir.mkdir(local_location) unless File.exist?(local_location)
        local_package_location = File.join(local_location, 'package.zip')

        download_latest_xcrc_release(local_package_location)

        if !system("unzip #{local_package_location} -d #{local_location}")
          throw "Unzipping XCRemoteCache failed"
        end 
      end

      def self.download_latest_xcrc_release(local_package_location)
        release_url = 'https://api.github.com/repos/spotify/XCRemoteCache/releases/latest'
        asset_url = nil
        
        URI.open(release_url) do |f|
          assets_array = JSON.parse(f.read)['assets']
          # Pick fat archive
          asset_array = assets_array.detect{|arr| arr['name'].include?(FAT_ARCHIVE_NAME_INFIX)}
          asset_url = asset_array['url']
        end

        if asset_url.nil? 
          throw "Downloading XCRemoteCache failed"
        end

        URI.open(asset_url, "accept" => 'application/octet-stream') do |f|
          File.open(local_package_location, "wb") do |file|
            file.puts f.read
          end
        end
      end

      def self.add_cflags!(options, key, value)
        return if options.fetch('OTHER_CFLAGS',[]).include?(' ' + value)
        options['OTHER_CFLAGS'] = remove_cflags!(options, key) << " #{key}=#{value}" 
      end

      def self.remove_cflags!(options, key)
        cflags_arr = options.fetch('OTHER_CFLAGS', ['$(inherited)'])
        cflags_arr = [cflags_arr] if cflags_arr.kind_of? String
        options['OTHER_CFLAGS'] = cflags_arr.delete_if {|flag| flag.start_with?(" #{key}=") }
        options['OTHER_CFLAGS']
      end

      def self.add_swiftflags!(options, key, value)
        return if options.fetch('OTHER_SWIFT_FLAGS','').include?(value)
        options['OTHER_SWIFT_FLAGS'] = remove_swiftflags!(options, key) + " #{key} #{value}" 
      end

      def self.remove_swiftflags!(options, key)
        options['OTHER_SWIFT_FLAGS'] = options.fetch('OTHER_SWIFT_FLAGS', '$(inherited)').gsub(/\s+#{Regexp.escape(key)}\s+\S+/, '')
        options['OTHER_SWIFT_FLAGS']
      end

      # Uninstall the XCRemoteCache
      def self.disable_xcremotecache(user_project)
        user_project.targets.each do |target|
          disable_xcremotecache_for_target(target)
        end
        user_project.save()

        # Remove .lldbinit rewrite
        save_lldbinit_rewrite(nil) unless !@@configuration['modify_lldb_init']
      end

      # Returns the content (array of lines) of the lldbinit with stripped XCRemoteCache rewrite
      def self.clean_lldbinit_content(lldbinit_path)
        all_lines = []
        return all_lines unless File.exist?(lldbinit_path)
        File.open(lldbinit_path) { |file|
          while(line = file.gets) != nil
            line = line.strip
            if line == LLDB_INIT_COMMENT 
              # skip current and next lines
              file.gets
              next
            end
            all_lines << line
          end
        }
        all_lines
      end

      # Append source rewrite command to the lldbinit content
      def self.add_lldbinit_rewrite(lines_content, user_proj_directory)
        all_lines = lines_content.clone
        all_lines << LLDB_INIT_COMMENT
        all_lines << "settings set target.source-map #{FAKE_SRCROOT} #{user_proj_directory}"    
        all_lines << ""
        all_lines
      end

      def self.save_lldbinit_rewrite(user_proj_directory)
        lldbinit_lines = clean_lldbinit_content(LLDB_INIT_PATH)
        lldbinit_lines = add_lldbinit_rewrite(lldbinit_lines, user_proj_directory) unless user_proj_directory.nil?
        File.write(LLDB_INIT_PATH, lldbinit_lines.join("\n"), mode: "w")
      end

      Pod::HooksManager.register('cocoapods-xcremotecache', :post_install) do |installer_context|
        if @@configuration.nil?
          Pod::UI.puts "[XCRC] Warning! XCRemoteCache not configured. Call xcremotecache({...}) in Podfile to enable XCRemoteCache"
          next
        end

        user_project = installer_context.umbrella_targets[0].user_project

        begin    
          user_proj_directory = File.dirname(user_project.path)
          set_configuration_default_values

          unless @@configuration['enabled']
            Pod::UI.puts "[XCRC] XCRemoteCache disabled"
            disable_xcremotecache(user_project)
            next
          end

          validate_configuration()

          mode = @@configuration['mode']
          xccc_location = @@configuration['xccc_file']
          remote_commit_file = @@configuration['remote_commit_file']
          xcrc_location = @@configuration['xcrc_location']
          exclude_targets = @@configuration['exclude_targets'] || []
          exclude_build_configurations = @@configuration['exclude_build_configurations'] || []
          final_target = @@configuration['final_target']
          check_build_configuration = @@configuration['check_build_configuration']
          check_platform = @@configuration['check_platform']

          xccc_location_absolute = "#{user_proj_directory}/#{xccc_location}"
          xcrc_location_absolute = "#{user_proj_directory}/#{xcrc_location}"
          remote_commit_file_absolute = "#{user_proj_directory}/#{remote_commit_file}"

          # Download XCRC
          download_xcrc_if_needed(xcrc_location_absolute)

          # Save .rcinfo
          save_rcinfo(generate_rcinfo(), user_proj_directory)

          # Create directory for xccc & arc.rc location
          Dir.mkdir(BIN_DIR) unless File.exist?(BIN_DIR)

          # Remove previous xccc & arc.rc
          File.delete(remote_commit_file_absolute) if File.exist?(remote_commit_file_absolute)
          File.delete(xccc_location_absolute) if File.exist?(xccc_location_absolute)

          # Prepare XCRC
          begin
            prepare_result = YAML.load`#{xcrc_location_absolute}/xcprepare --configuration #{check_build_configuration} --platform #{check_platform}`
            unless prepare_result['result'] || mode != 'consumer'
              # Uninstall the XCRemoteCache for the consumer mode
              disable_xcremotecache(user_project)
              Pod::UI.puts "[XCRC] XCRemoteCache disabled - no artifacts available"
              next
            end
          rescue => error
            disable_xcremotecache(user_project)
            Pod::UI.puts "[XCRC] XCRemoteCache failed with an error: #{error}."
            next
          end

          # Attach XCRemoteCache to Pods targets
          installer_context.pods_project.targets.each do |target|
              next if target.name.start_with?("Pods-")
              next if target.name.end_with?("Tests")
              next if exclude_targets.include?(target.name)
              enable_xcremotecache(target, "../#{xcrc_location}", "../#{xccc_location}", mode, exclude_build_configurations, final_target)
          end

          # Create .rcinfo into `Pods` directory as that .xcodeproj reads configuration from .xcodeproj location
          pods_proj_directory = installer_context.sandbox_root
          
          # Manual .rcinfo generation (in YAML format)
          save_rcinfo({'extra_configuration_file' => "#{user_proj_directory}/.rcinfo"}, pods_proj_directory)

          installer_context.pods_project.save()

          # Attach XCRC to the app targets
          user_project.targets.each do |target|
              next if exclude_targets.include?(target.name)
              enable_xcremotecache(target, xcrc_location, xccc_location, mode, exclude_build_configurations, final_target)
          end

          # Set Target sourcemap
          if @@configuration['modify_lldb_init']
            save_lldbinit_rewrite(user_proj_directory)
          else
            Pod::UI.puts "[XCRC] lldbinit modification is disabled. Debugging may behave weirdly"
            Pod::UI.puts "[XCRC] put \"settings set target.source-map #{FAKE_SRCROOT} \#{your_project_directory}\" to your \".lldbinit\" "
          end

          user_project.save()
          Pod::UI.puts "[XCRC] XCRemoteCache enabled"
        rescue Exception => e
          Pod::UI.puts "[XCRC] XCRemoteCache disabled with error: #{e}"
          puts e.full_message(highlight: true, order: :top)
          disable_xcremotecache(user_project)
        end
      end
    end
  end
end
