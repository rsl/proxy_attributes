require 'test/unit'

begin
  require File.dirname(__FILE__) + '/../../../config/environment'
rescue LoadError
  require 'rubygems'
  gem 'activerecord'
  require 'active_record'
  
  RAILS_ROOT = File.dirname(__FILE__) 
end

require File.join(File.dirname(__FILE__), '../init')

ActiveRecord::Base.establish_connection(:adapter => "sqlite3", :dbfile => "proxy_attributes.sqlite3")

ActiveRecord::Migration.verbose = false
ActiveRecord::Schema.define(:version => 1) do
  create_table :documents, :force => true do |t|
    t.string :title
  end

  create_table :categories, :force => true do |t|
    t.string :title
  end

  create_table :categorizations, :force => true do |t|
    t.integer :document_id, :category_id
  end
  
  create_table :tags, :force => true do |t|
    t.string :title
  end
  
  create_table :taggings, :force => true do |t|
    t.integer :document_id, :tag_id
  end
  
  create_table :attachments, :force => true do |t|
    t.integer :document_id
    t.string :title
  end
  
  create_table :badges, :force => true do |t|
    t.integer :document_id
    t.string :title
  end
  
  create_table :mystery_meats, :force => true do |t|
    t.integer :document_id
    t.string :meat
  end
end
ActiveRecord::Migration.verbose = true

class Document < ActiveRecord::Base
  has_many :categorizations
  has_many :categories, :through => :categorizations
  
  has_many :taggings
  has_many :tags, :through => :taggings
  
  has_many :attachments
  has_many :badges
  has_many :mystery_meats
  
  proxy_attributes do
    by_ids :categories, :badges
    by_string :tags => :title, :mystery_meats => :meat
    by_force :attachments
  end
  
  validates_presence_of :title
end

class Category < ActiveRecord::Base
  has_many :categorizations
  has_many :documents, :through => :categorizations
  
  validates_presence_of :title
end

class Categorization < ActiveRecord::Base
  belongs_to :document
  belongs_to :category
end

class Tag < ActiveRecord::Base
  has_many :taggings
  has_many :documents, :through => :taggings
  
  validates_presence_of :title
end

class Tagging < ActiveRecord::Base
  belongs_to :document
  belongs_to :tag
end

class Attachment < ActiveRecord::Base
  belongs_to :document
end

class Badge < ActiveRecord::Base
  belongs_to :document
end

class MysteryMeat < ActiveRecord::Base
  belongs_to :document
end

class PostponeAssociationsTest < Test::Unit::TestCase
  def saveable_doc(optional = {})
    unsaveable_doc(optional.merge(:title => "Saveable"))
  end
  
  def unsaveable_doc(optional = {})
    Document.new(optional)
  end
  
  def setup
    # Just to be safe
    [Document, Category, Tag, Attachment, MysteryMeat].each do |foo|
      foo.delete_all
    end
  end
  
  def test_assigns_children_by_ids_if_parent_saves
    @cat = Category.create(:title => "Saved")
    @doc = saveable_doc(:category_ids => [@cat.id])
    @doc.save
    assert @doc.categories.include?(@cat)
    assert @cat.documents.include?(@doc)
  end
  
  def test_caches_children_ids_for_reassignment_if_parent_save_fails
    @cat = Category.create(:title => "Unsaved")
    @doc = unsaveable_doc(:category_ids => [@cat.id])
    @doc.save
    assert @doc.categories.empty?
    assert @cat.documents.empty?
    assert_equal [@cat.id], @doc.category_ids
  end
  
  def test_assigns_children_by_ids_plain_has_many_support
    @badge = Badge.create(:title => "Unattached")
    @doc = saveable_doc(:badge_ids => [@badge.id])
    @doc.save
    @badge.reload
    assert @doc.badges.include?(@badge)
    assert_equal @doc, @badge.document
    assert_equal [@badge.id], @doc.badge_ids
  end
  
  def test_creates_child_by_ids_if_parent_saves
    @doc = saveable_doc(:add_category => {:title => "Created"})
    @doc.save
    @cat = Category.find_by_title("Created")
    assert @doc.categories.include?(@cat)
    assert @cat.documents.include?(@doc)
  end
  
  def test_does_not_create_child_if_parent_save_fails
    @doc = unsaveable_doc(:add_category => {:title => "Not Created"})
    @doc.save
    assert @doc.categories.empty?
    assert_nil Category.find_by_title("Not Created")
  end
  
  def test_caches_attributes_for_reassignment_if_parent_save_fails
    @doc = unsaveable_doc(:add_category => {:title => "Not Created"})
    @doc.save
    # Man I wish Foo.new == Foo.new, but it doesn't
    assert_equal({"title" => "Not Created"}, @doc.add_category.attributes)
  end
  
  def test_add_child_returns_new_child
    @doc = unsaveable_doc
    # Man I wish Foo.new == Foo.new, but it doesn't
    assert @doc.add_category.is_a?(Category)
  end
  
  def test_add_child_doesnt_add_invalid_records
    @doc = saveable_doc(:add_category => {:title => " "})
    @doc.save
    assert @doc.categories.empty?
  end
  
  def test_add_child_creates_multiple_records
    @doc = saveable_doc(:add_category => {1 => {:title => "First"}, 2 => {:title => "Second"}})
    @doc.save
    assert Category.find_by_title("First")
    assert Category.find_by_title("Second")
    assert_equal 2, @doc.categories.count
  end
  
  def test_caches_multiple_attributes_for_reassignment_if_parent_save_fails
    @doc = unsaveable_doc(:add_category => {1 => {:title => "First"}, 2 => {:title => "Second"}})
    @doc.save
    # Man I wish Foo.new == Foo.new, but it doesn't
    assert_equal({"title" => "First"}, @doc.add_category[1].attributes)
    assert_equal({"title" => "Second"}, @doc.add_category[2].attributes)
  end
  
  def test_add_child_support_for_plain_has_many
    @doc = saveable_doc(:add_badge => {:title => "Clingy"})
    @doc.save
    @badge = Badge.find_by_title("Clingy")
    assert @doc.badges.include?(@badge)
    assert_equal @doc, @badge.document
  end
  
  def test_assigns_children_by_string_if_parent_saves
    @tag = Tag.create(:title => "prexisting")
    @doc = saveable_doc(:tags_as_string => "prexisting")
    @doc.save
    assert @doc.tags.include?(@tag)
    assert @tag.documents.include?(@doc)
  end
  
  def test_creates_children_by_string_if_parent_saves
    @doc = saveable_doc(:tags_as_string => "freshly created")
    @doc.save
    @tag = Tag.find_by_title("freshly created")
    assert @doc.tags.include?(@tag)
    assert @tag.documents.include?(@doc)
  end
  
  def test_assigns_and_creates_children_by_string_if_parent_saves
    @tag = Tag.create(:title => "stale")
    @doc = saveable_doc(:tags_as_string => "stale, minty fresh")
    @doc.save
    @new_tag = Tag.find_by_title("minty fresh")
    assert @doc.tags.include?(@tag)
    assert @doc.tags.include?(@new_tag)
    assert @tag.documents.include?(@doc)
    assert @new_tag.documents.include?(@doc)
  end
  
  def test_does_not_assign_children_by_string_if_parent_save_fails
    @tag = Tag.create(:title => "prexisting")
    @doc = unsaveable_doc(:tags_as_string => "prexisting")
    @doc.save
    assert @doc.tags.empty?
    assert @tag.documents.empty?
  end
  
  def test_does_not_create_children_by_string_if_parent_save_fails
    @doc = unsaveable_doc(:tags_as_string => "freshly unborn")
    @doc.save
    assert @doc.tags.empty?
    assert_nil Tag.find_by_title("freshly unborn")
  end
  
  def test_does_not_assign_or_create_children_by_string_if_parent_save_fails
    @tag = Tag.create(:title => "stale")
    @doc = unsaveable_doc(:tags_as_string => "stale, seedy mint")
    @doc.save
    assert @doc.tags.empty?
    assert @tag.documents.empty?
    assert_nil Tag.find_by_title("seedy mint")
  end
  
  def test_caches_string_for_reassignment_if_parent_save_fails
    @doc = unsaveable_doc(:tags_as_string => "hateful, bitter, soulless shit")
    @doc.save
    assert_equal "hateful, bitter, soulless shit", @doc.tags_as_string
  end
  
  def test_assigning_children_as_string_doesnt_add_duplicates
    @doc = saveable_doc(:tags_as_string => "check, , check")
    @doc.save
    assert_equal 1, @doc.tags.count
    assert_equal [Tag.find_by_title("check")], @doc.tags
  end
  
  def test_assigning_children_as_string_doesnt_add_blank
    @doc = saveable_doc(:tags_as_string => " ")
    @doc.save
    assert @doc.tags.empty?
  end
  
  def test_children_as_string_reader_should_return_empty_string_not_nil
    assert_equal "", Document.new.tags_as_string
  end
  
  def test_children_as_string_plain_has_many_support
    @doc = saveable_doc(:mystery_meats_as_string => "scoobish snack")
    @doc.save
    @mystery_meat = MysteryMeat.find_by_meat("scoobish snack")
    assert @doc.mystery_meats.include?(@mystery_meat)
    assert_equal @doc, @mystery_meat.document
  end
  
  def test_manage_child_updates_object
    @doc = saveable_doc(:add_tag => {:title => "updateable"})
    @doc.save
    @tag = Tag.find_by_title("updateable")
    @doc.update_attributes(:manage_tag => {@tag.id => {:title => "updated!"}})
    @tag.reload
    assert_equal "updated!", @tag.title
  end
  
  def test_manage_child_hash_returns_object_for_keys_with_objects
    @doc = saveable_doc(:tags_as_string => "manageable")
    @doc.save
    @tag = Tag.find_by_title("manageable")
    assert_equal @tag, @doc.manage_tag[@tag.id]
  end
  
  def test_manage_child_hash_raises_exception_for_keys_with_no_objects
    @doc = saveable_doc
    @doc.save
    assert_raises LuckySneaks::ProxyAttributes::ImproperAccess do
      @doc.manage_tag[nil]
    end
  end
  
  def test_adds_child_by_force_if_parent_saves
    @doc = saveable_doc(:add_attachment => {:title => "uploadable"})
    @doc.save
    @attachment = Attachment.find_by_title("uploadable")
    assert_equal [@attachment], @doc.attachments
    assert_equal @doc, @attachment.document
  end
  
  def test_add_child_by_force_creates_unassociated_child_when_parent_save_fails
    @doc = unsaveable_doc(:add_attachment => {:title => "unsaveable parent"})
    @doc.save
    @attachment = Attachment.find_by_title("unsaveable parent")
    assert @attachment.document.nil?
    # However...
    assert_equal [@attachment], @doc.attachments
    # Because...
    assert_equal [@attachment], @doc.attachments_with_postponed
    assert_equal @attachment.id.to_s, @doc.postponed_attachment_ids
    assert_equal [], @doc.attachments_without_postponed
  end
  
  def test_add_child_by_force_creates_multiple_records
    @doc = saveable_doc(:add_attachment => {"0" => {:title => "first attachment"},
      "1" => {:title => "second attachment"}})
    @doc.save
    @attachment_1 = Attachment.find_by_title("first attachment")
    @attachment_2 = Attachment.find_by_title("second attachment")
    assert @doc.attachments.include?(@attachment_1)
    assert @doc.attachments.include?(@attachment_2)
    assert_equal @doc, @attachment_1.document
    assert_equal @doc, @attachment_2.document
  end
  
  def test_postponed_child_ids_associates_records
    @attachment = Attachment.create!(:title => "pre-existing")
    @doc = saveable_doc(:postponed_attachment_ids => @attachment.id.to_s)
    @doc.save
    assert @doc.attachments.include?(@attachment)
    @attachment.reload
    assert_equal @doc, @attachment.document
  end
end
