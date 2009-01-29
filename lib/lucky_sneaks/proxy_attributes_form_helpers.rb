module LuckySneaks
  # TODO: Jesus this could use some loving!
  module ProxyAttributesFormHelpers
    # Simply a shortcut for the somewhat standard check_box_tag used for
    # <tt>has_and_belongs_to_many</tt> checkboxes popularized by Ryan Bates'
    # Railscast[http://railscasts.com/episodes/17]
    # 
    # The following examples are equivalent
    # 
    #   proxy_attributes_check_box_tag :document, :category_ids, category
    # 
    #   check_box_tag "document[category_ids][]", category.id, @document.category_ids.include?(category.id)
    # 
    # In addition, proxy_attributes_check_box_tag will add a hidden input tag with
    # with value of 0 in order to send the params when no value is checked.
    # 
    # Note: This method presumes the form_object_name is an instance variable.
    # You can override this by stating a true value for local_variable which
    # will force the helper to look for a local variable with the same name.
    #
    # PS: If you have a better/shorter name for this, I'm all ears. :)
    def proxy_attributes_check_box_tag(form_object_name, proxy_name, object_to_check, local_variable = false)
      method_name = "#{form_object_name}[#{proxy_name}][]"
      parent = local_variable && local_variables.include?(form_object_name.to_s) ? self.send(local_variable) : instance_variable_get("@#{form_object_name}")
      checked_value = parent.send(proxy_name).include?(object_to_check.id)
      tag = check_box_tag method_name, object_to_check.id, checked_value
      if previous_check_box_exists_for[method_name]
        check_box_tag method_name, object_to_check.id, checked_value
      else
        previous_check_box_exists_for[method_name] = true
        [
          hidden_field_tag(method_name, 0),
          check_box_tag(method_name, object_to_check.id, checked_value)
        ].join("\n")
      end
    end
    
  private
    def previous_check_box_exists_for
      @proxy_attributes_check_box_mapping ||= {}
    end
  end
end