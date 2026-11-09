require "active_storage/service/disk_service"

class ActiveStorage::Service::BundledService < ActiveStorage::Service::DiskService
  def initialize(root:, **options)
    super(root: root, public: true, **options)
  end

  def path_for(key)
    unless key.is_a?(String) && key.match?(/\Acw-demo-[a-z0-9-]+\.(?:jpg|png)\z/)
      raise ActiveStorage::InvalidKeyError, "Invalid bundled asset key"
    end
    File.join(root, key)
  end

  def upload(*)
    raise NotImplementedError, "Bundled assets are read-only"
  end
  alias_method :compose, :upload
  alias_method :url_for_direct_upload, :upload

  # Purging a database attachment must never remove versioned application assets.
  def delete(key); end
  def delete_prefixed(prefix); end

  private

  def public_url(key, **)
    path_for(key)
    "/demo-media/#{key}"
  end
end
