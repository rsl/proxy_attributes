module LuckySneaks
  module ProxyAttributes
    def self.included(base) # :nodoc:
      base.extend ClassMethods
      base.send :include, InstanceMethods
    end
    
    module ClassMethods
      # This is the meat of everything
      # 
      # TODO: More documentation
      # 
      # Note: By default, invalid child records are simply discarded.
      # If a child record has already been saved, invalid changes will not be saved.
      # ProxyAttributes was designed for simplifying form inputs and
      # works best in cases where invalid children can be ignored.
      # If you require validation for your children, you can use
      # <tt>dont_swallow_errors!</tt> within your <tt>proxy_attributes</tt>
      # block to raise LuckySneaks::ProxyAttributes::InvalidChildAssignment.
      # *You* are responsible for catching this exception in your controllers.
      # There will be an error on base noting what exactly failed.
      def proxy_attributes(&block)
        cattr_accessor :attributes_for_string, :dont_swallow_errors
        self.attributes_for_string = {}.with_indifferent_access
        
        integrator = LuckySneaks::ProxyIntegrator.new(self)
        integrator.instance_eval(&block)
        
        after_save :assign_postponed
      end
    end
    
    module InstanceMethods
      # Holds assignment hashes postponed for after_save
      # when the parent object is a new record.
      # This is really meant for use internally
      # but might come in handy if you need to examine if there
      # are postponed assignments elsewhere in your code.
      def postponed
        @postponed ||= {}
      end
    
    private
      def assign_postponed
        postponed.each do |association_id, assignment|
          assign_or_postpone association_id => assignment
        end
        unless postponed_errors.blank?
          errors.add :proxy_attribute_child_errors, postponed_errors.flatten!
          raise LuckySneaks::ProxyAttributes::InvalidChildAssignment
        end
      end
      
      def assign_or_postpone(assignment_hash)
        if new_record?
          postponed.merge! assignment_hash
        else
          assignment_hash.each do |association_id, assignment|
            if association_id =~ /_ids$/
              assignment.delete 0
              return if assignment == self.send("#{association_id}_without_postponed")
              assign_proxy_by_ids association_id, assignment
            elsif association_id =~ /_as_string$/
              return if assignment == self.send("#{association_id}_without_postponed")
              assign_proxy_by_string association_id, assignment
            elsif association_id =~ /^add_/
              return if assignment.values.all?{|v| v.blank?}
              if assignment.values.first.is_a?(Hash)
                assignment.each do |index, actual_assignment|
                  next if actual_assignment.values.all?{|v| v.blank?}
                  create_proxy association_id, actual_assignment
                end
              else
                create_proxy association_id, assignment
              end
            end
          end
        end
      end
      
      def assign_proxy_by_ids(association_id, array_of_ids)
        proxy = fetch_proxy(association_id.chomp("_ids"))
        
        self.send(proxy.through_reflection.name).clear
        self.send(proxy.name) << proxy.klass.find(array_of_ids)
      end
      
      def assign_proxy_by_string(association_id, string)
        association_id = association_id.chomp("_as_string")
        proxy = fetch_proxy(association_id)
        attribute = self.class.attributes_for_string[association_id.to_sym]
        
        self.send(proxy.through_reflection.name).clear
        self.send(proxy.name) << string.split(/,\s*/).map { |substring|
          next if substring.blank?
          member = proxy.klass.send("find_or_initialize_by_#{attribute}", substring)
          # Only return valid, saved members
          if member.save
            member
          else
            postpone_errors member
            # Don't add this member!
            nil
          end
        }.uniq.compact
      end
      
      def create_proxy(association_id, hash_of_attributes)
        proxy = fetch_proxy(association_id.sub(/add_/, ""))
        
        member = proxy.klass.new(hash_of_attributes)
        if member.save
          self.send(proxy.name) << member
        else
          postpone_errors member
        end
      end
      
      def fetch_proxy(association_id)
        self.class.reflect_on_association(association_id.pluralize.to_sym)
      end
      
      def postpone_errors(member)
        return unless self.class.dont_swallow_errors
        postponed_errors << member.errors.full_messages.map {|message|
          "#{member} could not be saved because: #{message}"
        }
      end
      
      def postponed_errors
        @postponed_errors ||= []
      end
    end
    
    class InvalidChildAssignment < StandardError; end
  end
end