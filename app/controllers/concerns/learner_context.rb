module LearnerContext
  extend ActiveSupport::Concern

  COOKIE_NAME = :course_workshop_learner

  included do
    before_action :prevent_progress_caching
  end

  private

  def current_learner_profile
    @current_learner_profile ||= LearnerProfile.find_or_create_by!(key: learner_key)
  end

  def learner_key
    if (Rails.env.development? || Rails.env.test?) && Rails.configuration.x.learning_progress.local_profile &&
        [ "127.0.0.1", "::1" ].include?(request.remote_ip) &&
        [ "localhost", "127.0.0.1", "::1", "[::1]" ].include?(request.host)
      return "local"
    end

    key = cookies.encrypted[COOKIE_NAME]
    return key if key.is_a?(String) && key.match?(/\A[a-f0-9]{64}\z/)

    key = SecureRandom.hex(32)
    cookies.encrypted[COOKIE_NAME] = {
      value: key, expires: 1.year.from_now, httponly: true, same_site: :lax, secure: request.ssl?
    }
    key
  end

  def prevent_progress_caching
    response.headers["Cache-Control"] = "private, no-store"
  end
end
