# Just a namespace, move along!
module LuckySneaks
  # Another namespace, keep moving!
  module ProxyAttributes
    def self.included(base) # :nodoc:
      base.extend ClassMethods
      base.send :include, InstanceMethods
    end
    
    module ClassMethods
      # Please read the README.rdoc[link:files/README_rdoc.html]
      # for a full explanation and example of this method
      def proxy_attributes(&block)
        class_inheritable_accessor :attributes_as_string_separator, :dont_swallow_errors
        class_inheritable_array :forceable_associations
        class_inheritable_hash :attributes_for_string, :before_creating_procs
        self.attributes_for_string ||= {}.with_indifferent_access
        self.forceable_associations ||= []
        self.before_creating_procs ||= {}.with_indifferent_access
        
        integrator = LuckySneaks::ProxyIntegrator.new(self)
        integrator.instance_eval(&block)
        
        before_validation :assign_postponed_forceables
        after_save :assign_postponed
      end
    end
    
    module InstanceMethods # :nodoc:
    private
      # Holds assignment hashes postponed for after_save
      # when the parent object is a new record.
      # This is really meant for use internally
      # but might come in handy if you need to examine if there
      # are postponed assignments elsewhere in your code.
      def postponed
        @postponed ||= {}
      end
      
      def postponed_forceables
        @postponed_forceables ||= {}
      end
      
      def assign_postponed
        postponed.each do |association_id, assignment|
          assign_or_postpone association_id => assignment
        end
        unless postponed_errors.blank?
          errors.add :proxy_attribute_child_errors, postponed_errors.flatten!
          raise LuckySneaks::ProxyAttributes::InvalidChildAssignment
        end
      end
      
      def assign_postponed_forceables
        postponed_forceables.each do |association_id, assignment|
          create_proxy_members association_id, assignment
        end
        unless postponed_errors.blank?
          errors.add :proxy_attribute_child_errors, postponed_errors.flatten!
          raise LuckySneaks::ProxyAttributes::InvalidChildAssignment
        end
      end
      
      def assign_or_postpone(assignment_hash)
        if new_record?
          assignment_hash.each do |association_id, assignment|
            if forceable?(association_id)
              if postponed_forceables[association_id]
                postponed_forceables[association_id] | assignment
              else
                postponed_forceables.merge! assignment_hash
              end
            else
              if postponed[association_id]
                postponed[association_id] | assignment
              else
                postponed.merge! assignment_hash
              end
            end
          end
        else
          assignment_hash.each do |association_id, assignment|
            if association_id =~ /_ids$/
              assignment.delete 0
              assign_proxy_members_by_ids association_id, assignment
            elsif association_id =~ /_as_string$/
              return if assignment == self.send("#{association_id}_without_postponed")
              assign_proxy_members_by_string association_id, assignment
            elsif association_id =~ /^add_/
              create_proxy_members association_id, assignment
            elsif association_id =~ /^manage_/
              assignment.each do |member_id, actual_assignment|
                manage_proxy_member association_id, member_id, actual_assignment
              end
            end
          end
        end
      end
      
      def assign_proxy_members_by_ids(association_id, array_of_ids)
        proxy = fetch_proxy(association_id.chomp("_ids"))
        
        reset_proxy(proxy)
        
        self.send("#{proxy.name}_without_postponed") << proxy.klass.find(array_of_ids)
      end
      
      def assign_proxy_members_by_string(association_id, string)
        association_id = association_id.chomp("_as_string")
        proxy = fetch_proxy(association_id)
        attribute = self.class.attributes_for_string[association_id.to_sym]
        
        reset_proxy(proxy)
        
        separator = case self.class.attributes_as_string_separator
        when "space"
          /\s+/
        else
          /,\s*/
        end
        self.send(proxy.name) << string.split(separator).map { |substring|
          next if substring.blank?
          member = proxy.klass.send("find_or_initialize_by_#{attribute}", substring)
          if before_creation_procs = self.class.before_creating_procs[association_id.singularize]
            before_creation_procs.each do |before_creation_proc|
              instance_exec member, &before_creation_proc
            end
          end
          if member.save
            member
          else
            postpone_errors member
            nil
          end
        }.uniq.compact
      end
      
      def create_proxy_member(association_id, hash_of_attributes)
        association_root = association_id.sub(/add_/, "")
        proxy = fetch_proxy(association_root)
        
        if manually_settable?(proxy) && !new_record?
          hash_of_attributes.merge!(proxy.primary_key_name => id)
        end
        
        member = proxy.klass.new(hash_of_attributes)
        if before_creation_procs = self.class.before_creating_procs[association_root]
          before_creation_procs.each do |before_creation_proc|
            instance_exec member, &before_creation_proc
          end
        end
        if member.save
          if !manually_settable?(proxy) || !new_record?
            self.send("#{proxy.name}_without_postponed") << member
          elsif forceable?(association_id)
            association_ids = "#{association_root}_ids"
            if postponed[association_ids].blank?
              postponed[association_ids] = [member.id]
            else
              postponed[association_ids] << member.id
            end
          end
        else
          postpone_errors member
        end
      end
      
      def manually_settable?(proxy)
        !proxy.options.any?{|key, value| [:through, :as].include? key}
      end
      
      def forceable?(association_id)
        self.class.forceable_associations.include?(association_id)
      end
      
      def create_proxy_members(association_id, assignment)
        return if assignment.values.all?{|v| v.blank?}
        if assignment.values.first.is_a?(Hash)
          assignment.each do |index, actual_assignment|
            next if actual_assignment.values.all?{|v| v.blank?}
            create_proxy_member association_id, actual_assignment
          end
        else
          create_proxy_member association_id, assignment
        end
      end
      
      def manage_proxy_member(association_id, member_id, hash_of_attributes)
        proxy = fetch_proxy(association_id.sub(/manage_/, ""))
        
        member = proxy.klass.find_by_id(member_id)
        unless member.update_attributes(hash_of_attributes)
          postpone_errors member
        end
      end
      
      def fetch_proxy(association_id)
        self.class.reflect_on_association(association_id.pluralize.to_sym)
      end
      
      def reset_proxy(proxy)
        if proxy.through_reflection
          self.send(proxy.through_reflection.name).clear
        else
          self.send("#{proxy.name}_without_postponed").clear
        end
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
    
    # Just a custom exception. Nothing to see here.
    # Seriously... This won't get raised unless you are prepared for it.
    # Trust me.
    class InvalidChildAssignment < StandardError; end
    
    # Raised when manage_tag[n] is called when there's no associated object with id = n
    class ImproperAccess < StandardError; end
  end
end