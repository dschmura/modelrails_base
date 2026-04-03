Rails.application.config.after_initialize do
  IconRegistry.eager_load! if Rails.application.config.eager_load
end
