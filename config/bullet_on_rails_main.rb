# Bullet 8.2.0 raises at load on Active Record 8.2; this hands it its 8.1 patches (#1337).
# spec/config/bullet_on_rails_main_spec.rb fails the day Bullet supports 8.2 itself.
require "bullet/dependency"

Bullet::Dependency.prepend(Module.new do
  def active_record81?
    super || (active_record8? && ::ActiveRecord::VERSION::MINOR == 2)
  end
end)

require "bullet"
