module LuckySneaks
  # This class is only used internally for generating additional methods
  # for ease of manipulating the proxy collections
  # 
  # Note: the terms of child and children is used throughout the documentation here
  # to denote the singular and plural [respectively] of the association proxy's class name
  class ProxyIntegrator # :nodoc:
    cattr_accessor :parent
    
    def initialize(klass)
      @@parent = klass
    end
    
    def dont_swallow_errors!
      parent.dont_swallow_errors = false
    end
    
    # Used to generate the missing child_ids= method for has_many :through
    # and wraps child_ids to keep track of postponed assignments
    def by_ids(*association_ids)
      association_ids.each do |association_id|
        association_singular = association_id.to_s.singularize
        
        parent.class_eval do
          define_method "#{association_singular}_ids=" do |array_of_id_strings|
            assign_or_postpone "#{association_singular}_ids" => array_of_id_strings.map(&:to_i)
          end
          
          define_method "#{association_singular}_ids_with_postponed" do
            postponed["#{association_singular}_ids"] ||
              self.send("#{association_singular}_ids_without_postponed")
          end
          alias_method_chain "#{association_singular}_ids", :postponed
        end
        
        chain_default_methods association_id
      end
    end
    
    # Used to generate children_as_string method[s] for the association
    def by_string(association_hash)
      association_hash.each do |association_id, attribute_for_string|
        parent.class_eval do
          self.attributes_for_string[association_id] = attribute_for_string.to_sym
          
          define_method "#{association_id}_as_string=" do |string|
            assign_or_postpone "#{association_id}_as_string" => string
          end
          
          # Note: This becomes children_as_string_without_postponed
          define_method "#{association_id}_as_string" do
            self.send(association_id).map(&self.class.attributes_for_string[association_id]).join(", ")
          end
          
          define_method "#{association_id}_as_string_with_postponed" do
            postponed["#{association_id}_as_string"] ||
              self.send("#{association_id}_as_string_without_postponed")
          end
          alias_method_chain "#{association_id}_as_string", :postponed
        end
        
        chain_default_methods association_id
      end
    end
    
    def by_force(*association_ids)
      association_ids.each do |association_id|
        association_singular = association_id.to_s.singularize
        
        parent.forceable_associations << "add_#{association_singular}"
        
        parent.class_eval do
          define_method "postponed_#{association_singular}_ids" do
            postponed_ids = postponed["#{association_id.to_s.singularize}_ids"]
            postponed_ids.blank? ? "" : postponed_ids.join(",")
          end
          
          define_method "postponed_#{association_singular}_ids=" do |array_of_id_strings|
            assign_or_postpone "#{association_singular}_ids" => array_of_id_strings.split(",").map(&:to_i)
          end
        end
      end
      
      by_ids *association_ids
    end
    
    # Adds default methods only
    def just_defaults(*association_ids)
      association_ids.each do |association_id|
        chain_default_methods association_id
      end
    end
    
  private
    # TODO: Explain this?
    def chain_default_methods(association_id)
      association_singular = association_id.to_s.singularize
      
      parent.class_eval do
        define_method "#{association_id}_with_postponed" do
          if new_record?
            if self.forceable_associations.include?("add_#{association_singular}")
              proxy = self.class.reflect_on_association(association_id)
              postponed_ids = postponed["#{association_id.to_s.singularize}_ids"]
              postponed_ids.blank? ? [] : proxy.klass.find(postponed_ids)
            else
              postponed[association_id] || []
            end
          else
            self.send("#{association_id}_without_postponed")
          end
        end
        alias_method_chain association_id, :postponed
        
        define_method "add_#{association_singular}=" do |hash_of_attributes|
          assign_or_postpone "add_#{association_singular}" => hash_of_attributes
        end
        
        define_method "add_#{association_singular}" do
          name = "add_#{association_singular}"
          var_name = "@#{name}"
          return instance_variable_get(var_name) if instance_variable_get(var_name)
          klass = association_singular.classify.constantize
          if postponed[name].is_a?(Hash) && postponed[name].values.first.is_a?(Hash)
            result = {}
            postponed[name].each do |key, value|
              result[key.to_i] = klass.new value
            end
            instance_variable_set var_name, result
          else
            instance_variable_set var_name, klass.new(postponed[name])
          end
        end
        
        define_method "manage_#{association_singular}=" do |hash_of_attributes|
          assign_or_postpone "manage_#{association_singular}" => hash_of_attributes
        end
        
        define_method "manage_#{association_singular}" do
          name = "@managed_#{association_singular}"
          if managed = instance_variable_get("@managed_#{association_singular}")
            managed
          else
            klass = association_singular.classify.constantize
            instance_variable_set("@managed_#{association_singular}",
              self.send(association_id).inject(Hash.new{|h, k| raise LuckySneaks::ProxyAttributes::ImproperAccess}){ |memo, member|
              # This is body to the inject block
              memo[member.id] = member
              memo
            })
          end
        end
      end
    end
  end
end