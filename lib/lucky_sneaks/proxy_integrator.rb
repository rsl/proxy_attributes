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
    
    # Used to generate children_as_string method[s] for the association. Accepts
    # optional <tt>:separator</tt> which should be either <tt>:comma</tt> [default] or
    # <tt>space</tt>.
    def by_string(association_hash)
      parent.attributes_as_string_separator = association_hash.delete(:separator).to_s || "comma"
      association_hash.each do |association_id, attribute_for_string|
        parent.class_eval do
          self.attributes_for_string[association_id] = attribute_for_string.to_sym
          
          define_method "#{association_id}_as_string=" do |string|
            assign_or_postpone "#{association_id}_as_string" => string
          end
          
          # Note: This becomes children_as_string_without_postponed
          define_method "#{association_id}_as_string" do
            self.send(association_id).map(&self.class.attributes_for_string[association_id]).join(
              case self.class.attributes_as_string_separator
              when "space"
                " "
              else
                ", "
              end
            )
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
            return if array_of_id_strings.blank?
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
    
    # Allows custom code to be executed before creating the child object. This is useful
    # in cases where an attribute on the child object depends on an attribute of its parent.
    # Example:
    # 
    #   class Document < ActiveRecord::Base
    #     # Document and Attachment both belong to Project
    #     proxy_attributes do
    #       just_defaults :attachments
    #       
    #       before_creating(:attachments) do |attachment|
    #         # Steal the project_id from the document
    #         attachment.project_id = self.project_id
    #       end
    #     end
    #   end
    def before_creating(*association_ids, &block)
      association_ids.each do |association_id|
        key = association_id.to_s.singularize
        parent.before_creating_procs[key] ||= []
        parent.before_creating_procs[key] << block
      end
    end
    
  private
    # TODO: Explain this?
    def chain_default_methods(association_id)
      association_singular = association_id.to_s.singularize
      
      parent.class_eval do
        add_name = "add_#{association_singular}"
        manage_name = "manage_#{association_singular}"
        
        define_method "#{association_id}_with_postponed" do
          if new_record?
            if forceable_associations.include?(add_name)
              proxy = self.class.reflect_on_association(association_id)
              postponed_ids = postponed["#{association_singular}_ids"]
              postponed_ids.blank? ? self.send("#{association_id}_without_postponed") : proxy.klass.find(postponed_ids)
            else
              postponed[association_id] || self.send("#{association_id}_without_postponed")
            end
          else
            self.send("#{association_id}_without_postponed")
          end
        end
        alias_method_chain association_id, :postponed
        
        define_method "#{add_name}=" do |hash_of_attributes|
          return if hash_of_attributes.blank?
          assign_or_postpone add_name => hash_of_attributes
        end
        
        define_method add_name do
          var_name = "@added_#{association_singular}"
          if added = instance_variable_get(var_name)
            added
          else
            klass = association_singular.classify.constantize
            if postponed[add_name].is_a?(Hash) && postponed[add_name].values.first.is_a?(Hash)
              result = {}
              postponed[add_name].each do |key, value|
                result[key.to_i] = klass.new value
              end
              instance_variable_set var_name, result
            else
              instance_variable_set var_name, klass.new(postponed[add_name])
            end
          end
        end
        
        define_method "#{manage_name}=" do |hash_of_attributes|
          return if hash_of_attributes.blank?
          assign_or_postpone manage_name => hash_of_attributes
        end
        
        define_method manage_name do
          var_name = "@managed_#{association_singular}"
          if managed = instance_variable_get(var_name)
            managed
          else
            klass = association_singular.classify.constantize
            instance_variable_set(var_name,
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