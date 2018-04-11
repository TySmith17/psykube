class Psykube::Actor
  @digest : String?
  @git_data : StringMap?
  @metadata : StringMap?
  @raw_metadata : StringMap?
  @manifest : Manifest::Any?
  @template : Crustache::Syntax::Template
  @build_contexts : Array(BuildContext)?
  getter cluster_name : String?
  getter basename : String
  getter tag : String?
  getter context : String? = nil
  getter namespace : String = "default"
  getter dir : String = "."

  delegate to_json, to: generate

  def initialize(io, cluster_name = nil, context = nil, namespace = nil, basename = nil, tag = nil)
    @namespace = namespace if namespace
    raw_yaml = String.build { |string_io| IO.copy(io, string_io) }
    @template = Crustache.parse raw_yaml
    @cluster_name = cluster_name
    @tag = tag
    @basename = basename || [registry_host, registry_user, name].compact.join('/')
    @namespace = namespace || cluster.namespace || manifest.namespace || "default"
    @context = context || cluster.context || manifest.context
  end

  def cluster
    raise Generator::ValidationError.new("cluster argument required for manifests defining clusters") if !cluster_name && !manifest.clusters.empty?
    manifest.get_cluster(cluster_name || "")
  end

  def generate : Pyrite::Api::Core::V1::List
    manifest.generate(self)
  end

  def all_build_contexts
    (build_contexts + init_build_contexts).uniq
  end

  def build_contexts
    @build_contexts ||= manifest.get_build_contexts(cluster_name: @cluster_name || "", basename: basename, tag: @tag, build_context: @dir).uniq
  end

  def init_build_contexts
    @build_contexts ||= manifest.get_init_build_contexts(cluster_name: @cluster_name || "", basename: basename, tag: @tag, build_context: @dir).uniq
  end

  def manifest
    @manifest ||= Manifest.from_yaml(template_result metadata)
  end

  def name
    NameCleaner.clean([prefix, manifest.name, suffix].compact.join)
  end

  def template_result(metadata : StringMap = metadata)
    Crustache.render @template, {
      "metadata" => escaped(metadata),
      "git"      => escaped(git_data),
      "env"      => escaped(env_hash),
    }
  end

  private def ci_branch
    ENV["TRAVIS_BRANCH"]? || ENV["CIRCLE_BRANCH"]?
  end

  private def ci_sha
    ENV["TRAVIS_COMMIT"]? || ENV["CIRCLE_SHA1"]?
  end

  private def ci_tag
    ENV["TRAVIS_TAG"]? || ENV["CIRCLE_TAG"]?
  end

  private def env_hash
    ENV.keys.each_with_object(StringMap.new) { |k, h| h[k] = ENV[k] }
  end

  private def escaped(hash : StringMap)
    hash.each_with_object(StringMap.new) do |(k, v), h|
      h[k] = v.nil? || v.empty? ? "null" : [v].to_yaml.lines[1].lchop("-").strip
    end
  end

  private def git_data
    @git_data ||= Dir.cd(dir) do
      {"sha" => git_sha, "branch" => git_branch, "tag": git_tag}
    end
  end

  private def git_branch
    ci_branch || `git rev-parse --abbrev-ref HEAD`.strip
  end

  private def git_sha
    ci_sha || `git rev-parse HEAD`.strip
  end

  private def git_tag
    ci_tag || `git describe --exact-match --abbrev=0 --tags 2> /dev/null`.strip
  end

  private def prefix
    cluster.prefix || manifest.prefix
  end

  private def metadata
    @metadata ||= {
      "cluster_name" => @cluster_name || "",
      "namespace"    => @namespace,
    }
  end

  private def registry_host
    cluster.registry_host || manifest.registry_host
  end

  private def registry_user
    cluster.registry_user || manifest.registry_user
  end

  private def suffix
    cluster.suffix || manifest.suffix
  end
end