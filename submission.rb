##
# A façade class for consumers which collects associated models. Replicates setters and save methods for bulk assigning
# an entire set of records for a campaign. To begin, call #new or #create
# or use the built in finder to select an existing Comsumer by any property with #where. Without attributes, new will instigate
# a new Consumer instance for filling. #new and #create must be passed a masquerade attribute.
# Validators are used to determine the page a user should be on. If all requirements for a page are met, 
# then the stage will be incremented. This is how the user journey is defined.
# next_stage is provided to indicate where buttons/forms should redirect affer submission to attempt to get to the next stage.
class Submission
  include ActiveRecord::Validations
  validate :all_models_validate
  attr_accessor :stage, :name, :email
  attr_accessor :facebook_identifier, :facebook_access_token, :facebook_access_token_expiry, :facebook_cancelled

  STAGES = [:likegate, :landing, :login, :loggedin, :details, :share]

  # Dynamic validators are included in #instigate_validators!
  validates_acceptance_of   :page_like, accept: true,   if: :stage_likegate
  validates_presence_of     :facebook_identifier,       if: :stage_login,     unless: :facebook_cancelled
  validates_presence_of     :facebook_access_token,     if: :stage_loggedin,  unless: :facebook_cancelled
  validates_presence_of     :name, :email,              if: :stage_details, message: I18n.t(:mandatory_generic_validation_error)
  validates_email_format_of :email,                     if: :stage_details, message: I18n.t(:email_validation_error)
  # TODO: logged in validator to get past :stage_loggedin

  # New Submission instance for reading / writing individual properties
  # #new([@consumer|@masquerade,] [masquerade: @masquerade, consumer: @consumer])
  # Requires an argument named +masquerade+ or as the first property. Optionally takes a +consumer+
  def initialize *args
    opts = args.extract_options!
    @masquerade = opts.delete(:masquerade)
    @consumer = opts.delete(:consumer)
    @masquerade = args.shift if args.first.kind_of? Masquerade
    @consumer = args.shift if args.first.kind_of? Consumer
    raise ArgumentError, 'Missing masquerade argument' unless @masquerade.kind_of? Masquerade
    @consumer ||= @masquerade.biggest_fan_campaign.consumers.new
    self.page_like = true
    instigate_details_accessors!
    instigate_validators!
    fill_properties opts
  end

  # Creates an entire set of records from a big hash
  # #create(masquerade: @masquerade, [name: , twitter: ... ])
  # Requires an argument named +masquerade+. Further arguments are used to fill properties
  def self.create *args
    opts = args.extract_options!
    instance = self.new opts.delete(:masquerade)
    instance.send :fill_properties, opts
    instance.save
    instance
  end

  ## Updates any properties passed in
  def update *args
    opts = args.extract_options!
    fill_properties opts
    self.save
  end

  # Tell all records to save. Returns an array of booleans
  def save
    return false unless self.valid?
    self.stage # Reassess stage for moving forward
    ![@consumer.save].concat(@consumer.details.map(&:save)).include? false
  end

  # Soft-search for a Consumer by any properties. New instance initialized if none found.
  # Requires an argument named +masquerade+
  def self.where attributes
    masquerade = attributes.delete(:masquerade)
    self.where!(attributes)
    rescue ActiveRecord::RecordNotFound
      self.new masquerade
  end

  # Hard-search for a Consumer by any properties. Raises ActiveRecord::RecordNotFound
  def self.where! attributes
    consumer = Consumer.where(attributes).first!
    self.new consumer, masquerade: Masquerade.new(consumer.biggest_fan_campaign)
  end

  # Accessors via consumer
  def id
    @consumer.id
  end
  #
  def to_key
    @consumer.to_key
  end
  #
  def to_param
    @stage
  end
  #
  def to_model
    self
  end
  #
  def persisted?
    @consumer.persisted?
  end
  #
  def new_record?
    @consumer.new_record?
  end
  #
  def consumer
    @consumer
  end
  #
  def masquerade
    @masquerade
  end
  # Facebook Identifier is not going to be included in fields, so an accessor must be implicitly defined routing to consumer.
  def facebook_identifier
    @consumer.facebook_identifier
  end
  #
  def facebook_identifier= value
    @consumer.facebook_identifier = value
  end
  # Route to consumer 
  def facebook_access_token
    @consumer.facebook_access_token
  end
  #
  def facebook_access_token= value
    @consumer.facebook_access_token = value
  end
  # Route to consumer
  def facebook_access_token_expiry
    @consumer.facebook_identifier
  end
  #
  def facebook_access_token_expiry= value
    @consumer.facebook_access_token_expiry = value
  end
  
  # Run through validations for each form stage until valid then return that stage.
  # This enables the user journey to flow based on fulfilling entry requirements.
  def stage
    STAGES.each do |stage|
      @stage = stage
      break unless self.valid?
    end
    @stage
  end

  # Returns next stage in journey based on current stage
  def next_stage
    # Find stage in constant and return next array item
    current_index = STAGES.index stage
    STAGES[current_index + 1]
  end

  # Returns previous stage in journey based on current stage
  def previous_stage
    # Find stage in constant and return next array item
    current_index = STAGES.index stage
    STAGES[current_index - 1]
  end

  # Adds errors from consumer and details models
  def all_models_validate
    errors.add consumer.errors unless consumer.valid?
    consumer.details.each do |detail|
      errors.add detail.errors unless detail.valid?
    end
  end

  # Define helper methods for each stage. Returns boolean. True if stage is current
  STAGES.each do |stage|
    self.class_eval do
      define_method("stage_#{stage}") do
        # instance current stage
        @stage == stage
      end
    end
  end

  def self.reflect_on_association *args # :nodoc:
    # Don't use reflectors for association mapping
    false
  end

  # Dump to marshal by extracting relevant properties.
  # Possibly a performance hit: Using YAML to do the hard work
  def marshal_dump
    # Grab all instance variables, mapping records to IDs
    instance_values.map do |attribute, value|
      if value.respond_to? :id
        attribute = "#{attribute}_id"
        value = value.id
      end
      {attribute => value}
    end.reduce(:merge)
  end

  # Restore properties from a marshal
  # Possibly a performance hit: Loading dump via YAML and having the class instance generated by Marshal too.
  def marshal_load dump
    # Run through marshaled attributes and load records by ID
    attributes = dump.except('errors').map do |attribute, value|
      attribute_symbol = attribute.to_sym
      if id_match = attribute.match(/(.+)_id$/)
        klass = id_match[1].classify.constantize
        begin
          value = klass.find value
          attribute_symbol = attribute.gsub(/_id$/, '').to_sym
        rescue ActiveRecord::RecordNotFound
          attribute_symbol = value = nil
        end
      end
      {attribute_symbol => value}
    end.reduce(:merge).except(nil)

    self.send :initialize, attributes
  end

  # Restore from YAML, running initializer methods to fill properties and meta-methods.
  def self.from_yaml yaml
    instance = YAML::load yaml
    instance.send :instigate_details_accessors!
    instance.send :instigate_validators!
    instance.send :fill_properties, :skip_unknown, instance.instance_values
    instance
  end

  private

  def fill_properties *args
    opts = args.extract_options!
    skip_unknown = args.first == :skip_unknown
    opts.each do |property, attributes|
      begin
        self.send("#{property.to_s}=", attributes)
      rescue NoMethodError
        next if skip_unknown
        raise ActiveRecord::UnknownAttributeError.new( self, property.to_s )
      end
    end
  end

  def instigate_details_accessors!
    @masquerade.questions.each do |question|
      next unless question.to_sym
      self.class_eval do
        attr_accessor question.to_sym
        define_method("#{question.to_sym}_record") {
          consumer.details.select {|d| d.name == question.to_s }.first || consumer.details.new( name: question.to_s )
        }
        define_method(question.to_sym){
          self.send("#{question.to_sym}_record").to_s
        }
        define_method("#{question.to_sym}=") { |answer|
          self.instance_variable_set "@#{question.to_sym}", answer
          self.send("#{question.to_sym}_record").value = answer
        }
      end
    end
    ##
    # Getter and Setter Methods for fields.
    @masquerade.fields.each do |field|
      if consumer.attributes.keys.include? field.to_sym.to_s
        # Fields native to the consumer table get sent there.
        # This will rely on strong params in controller to prevent injection.
        self.class_eval do
          define_method(field.to_sym) {
            consumer.send field.to_sym
          }
          define_method("#{field.to_sym}=") { |value|
            consumer.send "#{field.to_sym}=", value
          }
        end
      else
        # Foreign fields get a Detail generated for them.
        #
        self.class_eval do
          attr_accessor field.to_sym
          define_method("#{field.to_sym}_record") {
            consumer.details.select {|d| d.name == field.to_s }.first || consumer.details.new( name: field.to_s )
          }
          define_method(field.to_sym) {
            record = self.send("#{field.to_sym}_record")
            field.check_box_type? ? record.to_bool : record.to_s
          }
          define_method("#{field.to_sym}=") { |value|
            self.instance_variable_set "@#{field.to_sym}", value
            self.send("#{field.to_sym}_record").value = value
          }
        end
      end
    end
  end

  def instigate_validators!
    @masquerade.questions.each do |question|
      next unless question.to_sym
      self.class_eval do
        validates_presence_of question.to_sym, message: I18n.t(:mandatory_question_validation_error), if: :stage_landing
      end
    end
    @masquerade.fields.each do |field|
      # Explicit attributes will have their validators explcitly defined
      next if consumer.attributes.keys.include? field.to_sym.to_s
      self.class_eval do
        validates_presence_of field.to_sym, message: mandatory_validation_message(field), if: :stage_details if field.mandatory and !field.check_box_type?
        validates_email_format_of field.to_sym message: mandatory_validation_message(field), if: :stage_details if field.email_type?
        validates_acceptance_of field.to_sym, accept: true, allow_nil: false, message: mandatory_validation_message(field), if: :stage_details if field.mandatory and field.check_box_type?
        validates_word_count_of field.to_sym, if: :stage_details if field.long_text_type?
      end
    end
    # Questions page has the first long_text field on it, so validate it there.
    long_answer_field = @masquerade.long_text_fields.first
    self.class_eval do
      validates_presence_of long_answer_field.to_sym, message: mandatory_validation_message(long_answer_field), if: :stage_landing if long_answer_field
      validates_word_count_of long_answer_field.to_sym, if: :stage_landing if long_answer_field
    end
  end

  def self.mandatory_validation_message field
    if field.to_s.split.size > 1
      if field.check_box_type?
        I18n.t :mandatory_checkbox_validation_error
      else
        I18n.t :mandatory_generic_validation_error
      end
    else
      I18n.t :mandatory_field_validation_error, field: field.to_s.en.a.downcase
    end
  end
end