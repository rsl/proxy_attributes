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
  has_many :mystery_meats
  
  proxy_attributes do
    by_ids :categories, :attachments
    by_string :tags => :title, :mystery_meats => :meat
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
    Document.delete_all
    Category.delete_all
    Tag.delete_all
    Attachment.delete_all
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
    @attachment = Attachment.create(:title => "Unattached")
    @doc = saveable_doc(:attachment_ids => [@attachment.id])
    @doc.save
    @attachment.reload
    assert @doc.attachments.include?(@attachment)
    assert_equal @doc, @attachment.document
    assert_equal [@attachment.id], @doc.attachment_ids
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
    @doc = saveable_doc(:add_attachment => {:title => "Clingy"})
    @doc.save
    @attachment = Attachment.find_by_title("Clingy")
    assert @doc.attachments.include?(@attachment)
    assert_equal @doc, @attachment.document
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
  
  def test_manage_child_hash_returns_object_for_existing_keys
    @doc = saveable_doc(:tags_as_string => "manageable")
    @doc.save
    @tag = Tag.find_by_title("manageable")
    assert_equal @tag, @doc.manage_tag[@tag.id]
  end
  
  def test_manage_child_hash_returns_new_object_for_nil_keys
    @doc = saveable_doc
    # Man I wish Foo.new == Foo.new, but it doesn't
    assert @doc.manage_tag[nil].is_a?(Tag)
    assert @doc.manage_tag[nil].new_record?
  end
end
