Rails.application.config.x.learning_progress.local_profile =
  ENV.fetch("LOCAL_PROGRESS_ENABLED", Rails.env.development?.to_s) == "true"
