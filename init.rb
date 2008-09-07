require "lucky_sneaks/proxy_integrator"
require "lucky_sneaks/proxy_attributes"
require "lucky_sneaks/transaction_workarounds"
ActiveRecord::Base.send :include, LuckySneaks::TransactionWorkarounds
ActiveRecord::Base.send :include, LuckySneaks::ProxyAttributes

if defined?(ActionView)
  require "lucky_sneaks/proxy_attributes_form_helpers"
  ActionView::Base.send :include, LuckySneaks::ProxyAttributesFormHelpers
end