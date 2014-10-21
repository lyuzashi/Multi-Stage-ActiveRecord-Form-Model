##
# A façade class for campaigns which collects associated models. Replicates setters and save methods for bulk assigning
# an entire set of records for a campaign. To begin, call #new @biggest_fan_campaign or #create {contents:{...}, ...}
# or use the built in finder to select an existing BiggestFanCampaign by any property with #where
class Masquerade
  include ActiveRecord::Validations
  MODELS = [:questions, :answers, :tags, :contents, :fields, :options, :subscriptions]
  attr_accessor :biggest_fan_campaign
  attr_accessor *MODELS

  validate :all_models_validate

  def initialize campaign=nil #:nodoc:
    @campaign = campaign || BiggestFanCampaign.new
    @biggest_fan_campaign = @campaign

    instigate_name_finders!
  end

  def self.find id
    self.where id: id
  end

  # Soft-search for a BiggestFanCampaign by any properties. New instance initialized if none found
  def self.where *attributes
    self.where!(*attributes)
    rescue ActiveRecord::RecordNotFound
  end

  # Hard-search for a BiggestFanCampaign by any properties. Raises ActiveRecord::RecordNotFound
  def self.where! *attributes
    self.new BiggestFanCampaign.where(*attributes).first!
  end

  # Accessors via Biggest Fan Campaign
  def id
    biggest_fan_campaign.id
  end
  #
  def to_param
    biggest_fan_campaign.slug
  end
  #
  def to_key
    biggest_fan_campaign.to_key
  end
  #
  def to_model
    self
  end
  #
  def persisted?
    biggest_fan_campaign.persisted?
  end

  def biggest_fan_campaign= attributes
    @biggest_fan_campaign = BiggestFanCampaign.where(:id=>attributes.try(:id)).first_or_initialize
    attributes.each do |attribute, value|
      @biggest_fan_campaign.send("#{attribute}=", value)
    end
    @campaign = @biggest_fan_campaign
  end

  # Creates an entire set of records from a big hash
  def self.create attributes
    instance = self.new
    attributes.each do |model, attributes|
      instance.send("#{model.to_s}=", attributes)
    end
    instance.save
    instance.biggest_fan_campaign.send :generate_slug
    instance
  end

  # Update entire set of records, merging changes
  # For use with the PUT verb
  def update
  end

  # Replace entire set of records, removing attributes and models that are not passed
  # For use with the PATCH verb
  def replace
  end

  def save
    biggest_fan_campaign.save
    MODELS.each do |model|
      # Replace records in association proxies.
      record_array = instance_variable_get("@#{model.to_s}")
      self.send(model).try(:replace, record_array) if record_array.respond_to?(:each)
      self.send(model).each do |record|
        record.save
      end
    end
  end

  def all_models_validate
    MODELS.each do |model|
      record_array = instance_variable_get("@#{model.to_s}")
      if record_array.respond_to? :each
        record_array.each do |record|
          errors.add record.errors unless record.valid?
        end
      end
    end
  end

  MODELS.each do |model|

    # Public getters for associated models
    define_method("#{model.to_s}") { # CollectionProxy
      @campaign.send( model.to_s )
      # Setting the instance variable each time this is called will erase changes.
      #collection = @campaign.send( model.to_s )
      #instance_variable_set( "@#{model.to_s}", collection.try(:to_ary) )
      #collection
    }

    # Public setters for associated models
    define_method("#{model.to_s}=") { |incoming_data|
      incoming_data = [incoming_data].flatten
      outgoing = []
      incoming_data.each do |incoming|
        association = instance_variable_load model.to_s #Load array variable
        model_class = @campaign.send( model.to_s )
        if incoming.respond_to? :attributes # For ready-built instances
          association << incoming unless association.include? incoming
          outgoing    << incoming unless association.include? incoming
        else
          if incoming[:id].present?
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
            all_models = MODELS.dup << :biggest_fan_campaign
            child_associations_data = incoming.extract!(*all_models.map(&:to_s))
            # Generate a new record from attributes supplied
            new_record = model_class.new(incoming)
            association << new_record
            # Now run through associated models and send them through this creation function
            # Then reattach to the parent record.
            child_associations_data.to_a.each do |record_data|
              new_record.send("#{record_data[0]}=", self.send("#{record_data[0]}=", record_data[1]))
            end
            outgoing << new_record
          end
        end
        # Store updated array.
        instance_variable_set("@#{model.to_s}", association)
      end
      outgoing # Return array of created/updated records
    }

    # Method for removing records
    # TODO
  end

  # Dynamic finder for fields
  # E.g. +text_fields+ will return all fields with data_type of 'text'
  # Note: Calling any method that ends in _fields will load fields from database.
  def method_missing name, *args, &block
    if name.to_s =~ /^(.+)_fields$/
      self.fields.select {|f| f.data_type.to_s.parameterize.underscore == $1 } || super
    else 
      super
    end
  end

  private

  def instance_variable_load model
    # Instance variable getters for associated models
    collection = @campaign.send( model.to_s )
    instance_variable_get("@#{model.to_s}") ||
    instance_variable_set( "@#{model.to_s}", collection.try(:to_ary) )
  end

  def instigate_name_finders!
    # Add finder method to CollectionProxies 'by_name' and a shortcut 'n'
    MODELS.each do |model|
      model_class = @campaign.send( model.to_s )
      model_class.class_eval do
        define_method :by_name, lambda { |name|
          self.select {|a| a.name == name.to_s }.first
        }
        alias_method :n, :by_name
      end
    end
  end

end