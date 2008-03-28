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
    
    # TODO: Give this muscle and bone!
    def by_proc(*association_ids, &block)
      association_ids.each do |association_id|
        # Do something with that block there!
        
        chain_default_methods association_id
      end
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
      parent.class_eval do
        define_method "#{association_id}_with_postponed" do
          postponed[association_id] || self.send("#{association_id}_without_postponed")
        end
        alias_method_chain association_id, :postponed
        
        association_singular = association_id.to_s.singularize
        define_method "add_#{association_singular}=" do |hash_of_attributes|
          assign_or_postpone "add_#{association_singular}" => hash_of_attributes
        end
        
        define_method "add_#{association_singular}" do
          klass = association_singular.classify.constantize
          if postponed["add_#{association_singular}"].is_a?(Hash) && postponed["add_#{association_singular}"].values.first.is_a?(Hash)
            returning({}) do |reified|
              postponed["add_#{association_singular}"].each do |key, value|
                reified[key.to_i] = klass.new value
              end
            end
          else
            klass.new postponed["add_#{association_singular}"]
          end
        end
        
        define_method "manage_#{association_singular}" do
          klass = association_singular.classify.constantize
          self.send(association_id).inject(Hash.new(klass.new)) do |memo, member|
            memo[member.id] = member
            memo
          end
        end
      end
    end
  end
end