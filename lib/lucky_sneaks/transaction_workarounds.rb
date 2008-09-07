# Just a namespace, move along!
module LuckySneaks
  # I'm not terribly happy with this code so it might change at any notice.
  # There's a simpler way but it seems to bork in testing [but not actual use]
  # with sqlite3.
  # 
  # The purpose of all this is to allow <tt>assign_postponed_forceables</tt>
  # to run before the <tt>save</tt> transaction, so that it isn't rolled back
  # if the transaction rolls back.
  module TransactionWorkarounds
    def self.included(base)
      base.send :include, InstanceMethods
      
      base.class_eval do
        alias_method_chain :save, :transaction_hack
      end
    end
    
    module InstanceMethods
      def save_with_transaction_hack(perform_validation = true)
        assign_postponed_forceables rescue nil
        save_with_transactions
      end
    end
  end
end