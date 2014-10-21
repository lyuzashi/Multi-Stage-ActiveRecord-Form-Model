##
# The campaign. A polymorphic record of Template
class BiggestFanCampaign < ActiveRecord::Base
  include OutOfOrderEdgeable
  
  has_many :templates, as: :templatable, dependent: :destroy
  belongs_to :client
  has_many :subscriptions, dependent: :destroy
  has_many :tags, dependent: :destroy
  has_many :consumers, dependent: :destroy
  has_many :questions, dependent: :destroy
  has_many :answers, dependent: :destroy
  has_many :contents, dependent: :destroy
  has_many :options, dependent: :destroy
  has_many :fields, dependent: :destroy
  has_many :statuses, dependent: :destroy

  include MassAssignable

  accepts_nested_attributes_for :contents, allow_destroy: true
  accepts_nested_attributes_for :fields, allow_destroy: true
  accepts_nested_attributes_for :questions, allow_destroy: true
  accepts_nested_attributes_for :options, allow_destroy: true

  after_initialize :generate_slug, :apply_client

  def template
    self.templates.try(:first)
  end

  def to_param
    nil
  end

  private

  def generate_slug
    self.slug ||= self.name.parameterize.gsub(/[^0-9a-z ]/i, '') if self.name.present?
    self.save if self.slug_changed?
  end

  def apply_client
    return if self.client.present?
    return if self.new_record?
    self.client ||= self.template.try(:client)
    self.save if self.client_id_changed?
  end
end
