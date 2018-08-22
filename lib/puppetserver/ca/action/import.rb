require 'optparse'
require 'puppetserver/ca/utils/file_system'
require 'puppetserver/ca/x509_loader'
require 'puppetserver/ca/config/puppet'
require 'puppetserver/ca/utils/cli_parsing'

module Puppetserver
  module Ca
    module Action
      class Import
        include Puppetserver::Ca::Utils

        SUMMARY = "Import the CA's key, certs, and crls"
        BANNER = <<-BANNER
Usage:
  puppetserver ca import [--help]
  puppetserver ca import [--config PATH]
      --private-key PATH --cert-bundle PATH --crl-chain PATH

Description:
Given a private key, cert bundle, and a crl chain,
validate and import to the Puppet Server CA.

To determine the target location the default puppet.conf
is consulted for custom values. If using a custom puppet.conf
provide it with the --config flag

Options:
BANNER

        def initialize(logger)
          @logger = logger
        end

        def run(input)
          bundle_path = input['cert-bundle']
          key_path = input['private-key']
          chain_path = input['crl-chain']
          config_path = input['config']

          files = [bundle_path, key_path, chain_path, config_path].compact

          errors = FileSystem.validate_file_paths(files)
          return 1 if CliParsing.handle_errors(@logger, errors)

          loader = X509Loader.new(bundle_path, key_path, chain_path)
          return 1 if CliParsing.handle_errors(@logger, loader.errors)

          puppet = Config::Puppet.parse(config_path: config_path)
          return 1 if CliParsing.handle_errors(@logger, puppet.errors)

          target_locations = [puppet.settings[:cacert],
                              puppet.settings[:cakey],
                              puppet.settings[:cacrl],
                              puppet.settings[:serial],
                              puppet.settings[:cert_inventory]]
          errors = FileSystem.check_for_existing_files(target_locations)
          if !errors.empty?
            instructions = <<-ERR
If you would really like to replace your CA, please delete the existing files first.
Note that any certificates that were issued by this CA will become invalid if you
replace it!
ERR
            errors << instructions
            CliParsing.handle_errors(@logger, errors)
            return 1
          end

          FileSystem.ensure_dir(puppet.settings[:cadir])

          FileSystem.write_file(puppet.settings[:cacert], loader.certs, 0640)

          FileSystem.write_file(puppet.settings[:cakey], loader.key, 0640)

          FileSystem.write_file(puppet.settings[:cacrl], loader.crls, 0640)

          # Puppet's internal CA expects these file to exist.
          FileSystem.ensure_file(puppet.settings[:serial], "0x0001", 0640)
          FileSystem.ensure_file(puppet.settings[:cert_inventory], "", 0640)

          @logger.inform "Import succeeded. Find your files in #{puppet.settings[:cadir]}"
          return 0
        end

        def check_flag_usage(results)
          if results['cert-bundle'].nil? || results['private-key'].nil? || results['crl-chain'].nil?
            '    Missing required argument' + "\n" +
            '    --cert-bundle, --private-key, --crl-chain are required'
          end
        end

        def parse(args)
          results = {}
          parser = self.class.parser(results)

          errors = CliParsing.parse_with_errors(parser, args)

          if err = check_flag_usage(results)
            errors << err
          end

          errors_were_handled = CliParsing.handle_errors(@logger, errors, parser.help)

          exit_code = errors_were_handled ? 1 : nil

          return results, exit_code
        end

        def self.parser(parsed = {})
          OptionParser.new do |opts|
            opts.banner = BANNER
            opts.on('--help', 'Display this import specific help output') do |help|
              parsed['help'] = true
            end
            opts.on('--config CONF', 'Path to puppet.conf') do |conf|
              parsed['config'] = conf
            end
            opts.on('--private-key KEY', 'Path to PEM encoded key') do |key|
              parsed['private-key'] = key
            end
            opts.on('--cert-bundle BUNDLE', 'Path to PEM encoded bundle') do |bundle|
              parsed['cert-bundle'] = bundle
            end
            opts.on('--crl-chain CHAIN', 'Path to PEM encoded chain') do |chain|
              parsed['crl-chain'] = chain
            end
          end
        end
      end
    end
  end
end
