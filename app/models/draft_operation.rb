require "digest"

class DraftOperation < ApplicationRecord
  def self.perform!(request_key:, operation:, arguments:)
    fingerprint = Digest::SHA256.hexdigest(JSON.generate([ operation, canonical(arguments) ]))
    transaction(requires_new: true) do
      existing = find_by(request_key: request_key)
      return replay(existing, fingerprint) if existing

      receipt = create!(request_key: request_key, fingerprint: fingerprint)
      result = yield.deep_stringify_keys
      receipt.update!(result: result)
      result
    end
  rescue ActiveRecord::RecordNotUnique
    existing = find_by(request_key: request_key)
    raise unless existing
    replay(existing, fingerprint)
  end

  def self.replay(receipt, fingerprint)
    unless receipt.fingerprint == fingerprint
      raise Drafts::Error.new("request_conflict", "This request_key was used with different arguments. Use a new key for a new operation.")
    end
    receipt.result
  end

  def self.canonical(value)
    case value
    when Hash then value.stringify_keys.sort.to_h.transform_values { |item| canonical(item) }
    when Array then value.map { |item| canonical(item) }
    else value
    end
  end

  private_class_method :replay, :canonical
end
