##
# Overloads association setters so a hash of properties may be passed, generating the associated models.
# Must be included after association definitions.
# Rails NestedAttributes would be ideal, however due to the dynamic nature of the records only on the client-defined side
# their use would be limited. 
module MassAssignable
  extend ActiveSupport::Concern
  included do
    self.reflect_on_all_associations.each do |association_reflection|
      model = association_reflection.name
      # Public setters for associated models
      define_method("#{model.to_s}=") { |incoming_data|        
        next if incoming_data.nil?
        incoming_data = [incoming_data].flatten
        outgoing = []
        reflection = self.class.reflect_on_all_associations.select{|association| association.name == model }.try(:first)
        incoming_data.each do |incoming|
          model_class  = association = self.send( model.to_s ) || model.to_s.classify.constantize
          if incoming.respond_to? :attributes # For ready-built instances
            case reflection.try(:macro)
            when :belongs_to
              # Just use normal assignment
              super incoming_data.try(:first) || incoming_data
            else
              association << incoming unless association.include? incoming if association.present?
              outgoing    << incoming unless association.include? incoming if association.present?
            end
          else
            if incoming.try(:[], :id).present?
              # Use select to find in loaded array of records.
              target = association.select {|a| a.id == incoming[:id] }
            end
            if target
              # Handle patch, put and post. Follow rails 4 controller conventions
              target.attributes = incoming
              outgoing << target
            else
              # If the record doesn't exist and isn't an instance, generate one from supplied attributes.
              # Firstly, find attributes which look like models, strip them out
              child_associations_data = incoming.extract!(*self.class.reflect_on_all_associations.map(&:name).map(&:to_s))
              # Generate a new record from attributes supplied
              # TODO Test for ID and load rather than create?
              self.try(:save)
              model_class.try(:save)
              new_record = model_class.create(incoming)
              
              # Depending on the type of association, either concatinate the record to the association
              # or simply set it.
              
              case reflection.try(:macro)
              when :belongs_to
                self.send("#{model.to_s}=", new_record)
              else
                association << new_record if association.present?
              end
              
              # Now run through associated models and send them through this creation function
              # Then reattach to the parent record.
              child_associations_data.to_a.each do |record_data|
                new_record.send("#{record_data[0]}=", new_record.send("#{record_data[0]}=", record_data[1]))
              end
              outgoing << new_record
            end
          end
          # Store updated array.
        end
        outgoing.each do |record|
          record.try(:save)
        end
        outgoing # Return array of created/updated records
      }
    end
  end

  private

    def instance_variable_load model
      # Instance variable getters for associated models
      collection = self.send( model.to_s )
      instance_variable_get("@#{model.to_s}") ||
      instance_variable_set( "@#{model.to_s}", collection.try(:to_ary) )
    end
end