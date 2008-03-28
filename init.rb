require "lucky_sneaks/proxy_integrator"
require "lucky_sneaks/proxy_attributes"
ActiveRecord::Base.send :include, LuckySneaks::ProxyAttributes

if defined?(ActionView)
  require "lucky_sneaks/proxy_attributes_form_helpers"
  ActionView::Base.send :include, LuckySneaks::ProxyAttributesFormHelpers
end