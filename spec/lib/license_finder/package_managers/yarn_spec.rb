# frozen_string_literal: true

require 'spec_helper'
require 'fakefs/spec_helpers'
require 'json'

module LicenseFinder
  describe Yarn do
    let(:root) { '/fake-node-project' }
    it_behaves_like 'a PackageManager'

    let(:yarn1_shell_command_output) do
      {
        'type' => 'table',
        'data' => {
          'body' => [
            ['@sindresorhus/is', '0.7.0', 'MIT', 'https://github.com/sindresorhus/is.git', 'sindresorhus.com', 'Sindre Sorhus'],
            ['yn', '2.0.0', 'MIT', 'https://github.com/sindresorhus/yn.git', 'sindresorhus.com', 'Sindre Sorhus']
          ],
          'head' => %w[Name Version License URL VendorUrl VendorName]
        }
      }.to_json
    end

    let(:yarn_shell_command_output) do
      {
        'value' => 'MIT',
        'children' => {
          '@babel/preset-typescript@virtual:47c2c5b90818fd89a72#npm:7.18.6' => {
            'value' => {
              'locator' => '@babel/preset-typescript@virtual:47c2c5b90818fd89a72#npm:7.18.6',
              'descriptor' => '@babel/preset-typescript@virtual:47c2c5b90818fd89a72#npm:^7.13.0'
            },
            'children' => {
              'url' => 'https://github.com/babel/babel.git',
              'vendorName' => 'The Babel Team',
              'vendorUrl' => 'https://babel.dev/docs/en/next/babel-preset-typescript'
            }
          },
          '@types/jest@npm:26.0.24' => {
            'value' => {
              'locator' => '@types/jest@npm:26.0.24',
              'descriptor' => '@types/jest@npm:^26.0.23'
            },
            'children' => {
              'url' => 'https://github.com/DefinitelyTyped/DefinitelyTyped.git',
              'vendorUrl' => 'https://github.com/DefinitelyTyped/DefinitelyTyped/tree/master/types/jest'
            }
          }
        }
      }.to_json
    end

    describe '.prepare' do
      subject { Yarn.new(project_path: Pathname(root), logger: double(:logger, active: nil)) }

      include FakeFS::SpecHelpers
      before do
        FileUtils.mkdir_p(Dir.tmpdir)
        FileUtils.mkdir_p(root)
      end

      context 'when using Yarn 1.x projects' do
        before do
          allow(SharedHelpers::Cmd).to receive(:run).with('yarn -v').and_return(['1.9.4', '', cmd_success])
        end

        it 'should call yarn install with expected cli parameters' do
          expect(SharedHelpers::Cmd).to receive(:run).with('yarn install --ignore-engines --ignore-scripts')
                                                     .and_return([yarn1_shell_command_output, '', cmd_success])
          subject.prepare
        end

        context 'ignored_groups contains devDependencies' do
          subject { Yarn.new(project_path: Pathname(root), ignored_groups: 'devDependencies') }
          it 'should include a production flag' do
            expect(SharedHelpers::Cmd).to receive(:run).with('yarn install --ignore-engines --ignore-scripts --production')
                                                       .and_return([yarn1_shell_command_output, '', cmd_success])
            subject.prepare
          end
        end
      end

      context 'when using Yarn 3.x+ projects' do
        before do
          allow(SharedHelpers::Cmd).to receive(:run).with('yarn -v').and_return(['3.0.1', '', cmd_success])
        end

        it 'should call yarn install with no cli parameters' do
          expect(SharedHelpers::Cmd).to receive(:run).with('yarn install && yarn plugin import https://raw.githubusercontent.com/mhassan1/yarn-plugin-licenses/v0.7.2/bundles/@yarnpkg/plugin-licenses.js')
                                                     .and_return([yarn1_shell_command_output, '', cmd_success])
          subject.prepare
        end

        context 'ignored_groups contains devDependencies' do
          subject { Yarn.new(project_path: Pathname(root), ignored_groups: 'devDependencies') }

          it 'should include a production flag' do
            expect(SharedHelpers::Cmd).to receive(:run).with('yarn plugin import workspace-tools && yarn workspaces focus --all --production && yarn install && yarn plugin import https://raw.githubusercontent.com/mhassan1/yarn-plugin-licenses/v0.7.2/bundles/@yarnpkg/plugin-licenses.js')
                                                       .and_return([yarn1_shell_command_output, '', cmd_success])
            subject.prepare
          end
        end
      end

      context 'when using Yarn 2.x projects' do
        before do
          allow(SharedHelpers::Cmd).to receive(:run).with('yarn -v').and_return(['2.0.1', '', cmd_success])
        end

        it 'should call yarn install with no cli parameters' do
          expect(SharedHelpers::Cmd).to receive(:run).with('yarn install && yarn plugin import https://raw.githubusercontent.com/mhassan1/yarn-plugin-licenses/v0.6.0/bundles/@yarnpkg/plugin-licenses.js')
                                            .and_return([yarn1_shell_command_output, '', cmd_success])
          subject.prepare
        end

        context 'ignored_groups contains devDependencies' do
          subject { Yarn.new(project_path: Pathname(root), ignored_groups: 'devDependencies') }

          it 'should include a production flag' do
            expect(SharedHelpers::Cmd).to receive(:run).with('yarn plugin import workspace-tools && yarn workspaces focus --all --production && yarn install && yarn plugin import https://raw.githubusercontent.com/mhassan1/yarn-plugin-licenses/v0.6.0/bundles/@yarnpkg/plugin-licenses.js')
                                              .and_return([yarn1_shell_command_output, '', cmd_success])
            subject.prepare
          end
        end
      end
    end

    describe '#current_packages' do
      subject { Yarn.new(project_path: Pathname(root), logger: double(:logger, active: nil)) }

      include FakeFS::SpecHelpers
      before do
        FileUtils.mkdir_p(Dir.tmpdir)
        FileUtils.mkdir_p(root)
        allow(SharedHelpers::Cmd).to receive(:run).with('yarn -v').and_return(['1.0.1', '', cmd_success])
      end

      context 'when using Yarn v2.x+' do
        before do
          allow(SharedHelpers::Cmd).to receive(:run).with('yarn -v').and_return(['2.0.1', '', cmd_success])
        end

        it 'should call licenses plugin and displays packages' do
          allow(SharedHelpers::Cmd).to receive(:run).with('yarn config get modules-folder') do
            ["yarn_modules\n", '', cmd_success]
          end
          allow(SharedHelpers::Cmd).to receive(:run).with(Yarn::SHELL_COMMAND) do
            [yarn_shell_command_output, '', cmd_success]
          end

          expect(subject.current_packages.length).to eq 2
          expect(subject.current_packages.first.name).to eq '@babel/preset-typescript'
          expect(subject.current_packages.first.version).to eq '7.18.6'
          expect(subject.current_packages.first.license_names_from_spec).to eq ['MIT']
          expect(subject.current_packages.first.homepage).to eq 'https://babel.dev/docs/en/next/babel-preset-typescript'
          expect(subject.current_packages.first.authors).to eq 'The Babel Team'
          expect(subject.current_packages.first.install_path).to eq Pathname(root).join('yarn_modules', '@babel/preset-typescript')

          expect(subject.current_packages.last.name).to eq '@types/jest'
          expect(subject.current_packages.last.version).to eq '26.0.24'
          expect(subject.current_packages.last.license_names_from_spec).to eq ['MIT']
          expect(subject.current_packages.last.homepage).to eq 'https://github.com/DefinitelyTyped/DefinitelyTyped/tree/master/types/jest'
          expect(subject.current_packages.last.authors).to eq ''
          expect(subject.current_packages.last.install_path).to eq Pathname(root).join('yarn_modules', '@types/jest')
        end

        it 'displays incompatible packages with correct license type' do
          allow(SharedHelpers::Cmd).to receive(:run).with(Yarn::SHELL_COMMAND) do
            [
              '{"value":"Internal","children":{"@company/package@workspace:.":{"value":{"locator":"@company/package@workspace:.","descriptor":"@company/package@workspace:."},"children":{}}}}',
              '',
              cmd_success
            ]
          end

          expect(subject.current_packages.length).to eq 1
          expect(subject.current_packages.last.name).to eq '@company/package'
          expect(subject.current_packages.last.version).to eq '.'
          expect(subject.current_packages.last.license_names_from_spec).to eq ['Internal']
        end
      end

      it 'displays packages as returned from "yarn list"' do
        allow(SharedHelpers::Cmd).to receive(:run).with('yarn config get modules-folder') do
          ["yarn_modules\n", '', cmd_success]
        end
        allow(SharedHelpers::Cmd).to receive(:run).with(Yarn::SHELL_COMMAND + " --no-progress --cwd #{Pathname(root)}") do
          [yarn1_shell_command_output, '', cmd_success]
        end

        expect(subject.current_packages.length).to eq 2
        expect(subject.current_packages.first.name).to eq '@sindresorhus/is'
        expect(subject.current_packages.first.version).to eq '0.7.0'
        expect(subject.current_packages.first.license_names_from_spec).to eq ['MIT']
        expect(subject.current_packages.first.homepage).to eq 'sindresorhus.com'
        expect(subject.current_packages.first.authors).to eq 'Sindre Sorhus'
        expect(subject.current_packages.first.install_path).to eq Pathname(root).join('yarn_modules', '@sindresorhus/is')
        expect(subject.current_packages.last.name).to eq 'yn'
        expect(subject.current_packages.last.version).to eq '2.0.0'
        expect(subject.current_packages.last.license_names_from_spec).to eq ['MIT']
        expect(subject.current_packages.last.homepage).to eq 'sindresorhus.com'
        expect(subject.current_packages.last.authors).to eq 'Sindre Sorhus'
        expect(subject.current_packages.last.install_path).to eq Pathname(root).join('yarn_modules', 'yn')
      end

      it 'uses node_modules as fallback for install path' do
        allow(SharedHelpers::Cmd).to receive(:run).with('yarn config get modules-folder') do
          ["undefined\n", '', cmd_success]
        end
        allow(SharedHelpers::Cmd).to receive(:run).with(Yarn::SHELL_COMMAND + " --no-progress --cwd #{Pathname(root)}") do
          [yarn1_shell_command_output, '', cmd_success]
        end

        expect(subject.current_packages.last.install_path).to eq Pathname(root).join('node_modules', 'yn')
      end

      it 'displays incompatible packages with license type unknown' do
        allow(SharedHelpers::Cmd).to receive(:run).with(Yarn::SHELL_COMMAND + " --no-progress --cwd #{Pathname(root)}") do
          ['{"type":"info","data":"fsevents@1.1.1: The platform \"linux\" is incompatible with this module."}
            {"type":"info","data":"\"fsevents@1.1.1\" is an optional dependency and failed compatibility check. Excluding it from installation."}', '', cmd_success]
        end

        expect(subject.current_packages.length).to eq 1
        expect(subject.current_packages.last.name).to eq 'fsevents'
        expect(subject.current_packages.last.version).to eq '1.1.1'
        expect(subject.current_packages.last.license_names_from_spec).to eq ['unknown']
      end

      it 'handles json with non-ascii characters' do
        allow(SharedHelpers::Cmd).to receive(:run).with('yarn config get modules-folder') do
          ['yarn_modules', '', cmd_success]
        end
        allow(SharedHelpers::Cmd).to receive(:run).with(Yarn::SHELL_COMMAND + " --no-progress --cwd #{Pathname(root)}") do
          [{
            'type' => 'table',
            'data' => {
              'body' => [['stack-trace', '0.0.10', 'MIT', 'git://github.com/felixge/node-stack-trace.git', 'https://github.com/felixgö/node-stack-trace', 'Felix Geisendörfer']],
              'head' => %w[Name Version License URL VendorUrl VendorName]
            }
          }.to_json, '', cmd_success]
        end

        expect(subject.current_packages.length).to eq 1
        expect(subject.current_packages.first.name).to eq 'stack-trace'
        expect(subject.current_packages.first.version).to eq '0.0.10'
        expect(subject.current_packages.first.license_names_from_spec).to eq ['MIT']
        expect(subject.current_packages.first.homepage).to eq 'https://github.com/felixg?/node-stack-trace'
      end

      context 'ignored_groups contains devDependencies' do
        subject { Yarn.new(project_path: Pathname(root), ignored_groups: 'devDependencies') }
        it 'should include a production flag' do
          expect(SharedHelpers::Cmd).to receive(:run).with('yarn config get modules-folder')
                                                     .and_return(['yarn_modules', '', cmd_success])
          expect(SharedHelpers::Cmd).to receive(:run).with("#{Yarn::SHELL_COMMAND} --production --no-progress --cwd #{Pathname(root)}")
                                                     .and_return([yarn1_shell_command_output, '', cmd_success])
          subject.current_packages
        end
      end

      context 'packages contain workspace-aggregator' do
        it 'should remove the package' do
          allow(SharedHelpers::Cmd).to receive(:run).with('yarn config get modules-folder') do
            ['yarn_modules', '', cmd_success]
          end
          allow(SharedHelpers::Cmd).to receive(:run).with(Yarn::SHELL_COMMAND + " --no-progress --cwd #{Pathname(root)}") do
            [{
              'type' => 'table',
              'data' => {
                'body' => [['workspace-aggregator-8e9c6710-d159-44a9-b7eb-78831eed0c59', '', 'UNKNOWN', 'Unknown', 'Unknown', 'Unknown'],
                           ['stack-trace', '0.0.10', 'MIT', 'git://github.com/felixge/node-stack-trace.git', 'https://github.com/felixgö/node-stack-trace', 'Felix Geisendörfer']],
                'head' => %w[Name Version License URL VendorUrl VendorName]
              }
            }.to_json, '', cmd_success]
          end

          expect(subject.current_packages.length).to eq 1
          expect(subject.current_packages.first.name).to eq 'stack-trace'
          expect(subject.current_packages.first.version).to eq '0.0.10'
          expect(subject.current_packages.first.license_names_from_spec).to eq ['MIT']
          expect(subject.current_packages.first.homepage).to eq 'https://github.com/felixg?/node-stack-trace'
        end
      end

      context 'when the shell command fails' do
        it 'an error is raised' do
          allow(SharedHelpers::Cmd).to receive(:run).with(Yarn::SHELL_COMMAND + " --no-progress --cwd #{Pathname(root)}").and_return([nil, 'error', cmd_failure])

          expect { subject.current_packages }.to raise_error(/Command 'yarn licenses list --recursive --json --no-progress --cwd #{Pathname(root)}' failed to execute: error/)
        end
      end
    end

    describe '.prepare_command' do
      include FakeFS::SpecHelpers
      before do
        FileUtils.mkdir_p(Dir.tmpdir)
        FileUtils.mkdir_p(root)
      end

      context 'when in a Yarn 1.x project' do
        before do
          allow(SharedHelpers::Cmd).to receive(:run).with('yarn -v').and_return(['1.9.1', '', cmd_success])
        end

        subject { Yarn.new(project_path: Pathname(root), logger: double(:logger, active: nil)) }
        it 'returns the correct prepare method' do
          expect(subject.prepare_command).to eq('yarn install --ignore-engines --ignore-scripts')
        end
      end

      context 'when in a Yarn 2.x project' do
        before do
          allow(SharedHelpers::Cmd).to receive(:run).with('yarn -v').and_return(['2.1.9', '', cmd_success])
        end

        subject { Yarn.new(project_path: Pathname(root), logger: double(:logger, active: nil)) }
        it 'returns the correct prepare method' do
          expect(subject.prepare_command).to eq('yarn install && yarn plugin import https://raw.githubusercontent.com/mhassan1/yarn-plugin-licenses/v0.6.0/bundles/@yarnpkg/plugin-licenses.js')
        end
      end

      context 'when in a Yarn 3.x+ project' do
        before do
          allow(SharedHelpers::Cmd).to receive(:run).with('yarn -v').and_return(['3.5.9', '', cmd_success])
        end

        subject { Yarn.new(project_path: Pathname(root), logger: double(:logger, active: nil)) }
        it 'returns the correct prepare method' do
          expect(subject.prepare_command).to eq('yarn install && yarn plugin import https://raw.githubusercontent.com/mhassan1/yarn-plugin-licenses/v0.7.2/bundles/@yarnpkg/plugin-licenses.js')
        end
      end
    end

    describe '.package_management_command' do
      it 'returns the correct package management command' do
        expect(subject.package_management_command).to eq('yarn')
      end
    end
  end
end
