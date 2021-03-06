# encoding: utf-8
require 'yaml'
require_relative 'git-client'

class BuildpackDependencyUpdater
  attr_reader :dependency
  attr_reader :buildpack
  attr_reader :buildpack_dir
  attr_reader :binary_builds_dir
  attr_reader :dependency_version

  def self.create(dependency, *args)
    raise "Unsupported dependency" unless const_defined? dependency.capitalize
    const_get(dependency.capitalize).new(dependency, *args)
  end

  def initialize(dependency, buildpack, buildpack_dir, binary_builds_dir)
    @dependency = dependency
    @buildpack = buildpack
    @buildpack_dir = buildpack_dir
    @binary_builds_dir = binary_builds_dir
    @dependency_version, @url, @md5 = get_dependency_info(dependency, binary_builds_dir)
  end

  def run!
    manifest_file = File.join(buildpack_dir, "manifest.yml")
    buildpack_manifest = YAML.load_file(manifest_file)

    buildpack_manifest = perform_dependency_update(buildpack_manifest)
    buildpack_manifest = perform_dependency_specific_changes(buildpack_manifest, dependency)

    File.open(manifest_file, "w") do |file|
      file.write(buildpack_manifest.to_yaml)
    end
  end

  private

  def perform_dependency_update(buildpack_manifest)
    buildpack_manifest["dependencies"].delete_if {|dep| dep["name"] == dependency}
    dependency_hash = {
      "name"      => dependency,
      "version"   => dependency_version,
      "uri"       => @url,
      "md5"       => @md5,
      "cf_stacks" => ["cflinuxfs2"]
    }
    buildpack_manifest["dependencies"] << dependency_hash
    buildpack_manifest
  end
end

class BuildpackDependencyUpdater::Godep < BuildpackDependencyUpdater
  def get_dependency_info(dependency, binary_builds_dir)
    git_commit_message = GitClient.last_commit_message(binary_builds_dir)

    /.*filename:\s+binary-builder\/(godep-(\w*)-linux-x64.tgz).*md5:\s+(\w*)\,.*/.match(git_commit_message)
    dependency_filename = $1
    dependency_version = $2
    md5 = $3
    url = "https://pivotal-buildpacks.s3.amazonaws.com/concourse-binaries/#{dependency}/#{dependency_filename}"

    [dependency_version, url, md5]
  end

  def perform_dependency_specific_changes(buildpack_manifest, dependency)
    buildpack_manifest["url_to_dependency_map"].delete_if {|dep| dep["name"] == dependency}
    dependency_hash = {
      "match"   => dependency,
      "name"    => dependency,
      "version" => dependency_version
    }
    buildpack_manifest["url_to_dependency_map"] << dependency_hash
    buildpack_manifest
  end
end

class BuildpackDependencyUpdater::Composer < BuildpackDependencyUpdater
  def get_dependency_info(dependency, binary_builds_dir)
    git_commit_message = GitClient.last_commit_message(binary_builds_dir)

    dependency_version = git_commit_message[/filename:\s+binary-builder\/composer-([\d\.]*).phar/, 1]
    md5 = git_commit_message[/md5:\s+(\w+)/, 1]
    url ="https://pivotal-buildpacks.s3.amazonaws.com/php/binaries/trusty/composer/#{dependency_version}/composer.phar"

    [dependency_version, url, md5]
  end

  def perform_dependency_specific_changes(buildpack_manifest, dependency)
    buildpack_manifest
  end
end
