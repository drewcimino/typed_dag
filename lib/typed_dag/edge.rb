require 'active_support/concern'
require 'typed_dag/configuration'
require 'typed_dag/sql'

module TypedDag::Edge
  extend ActiveSupport::Concern

  included do
    include InstanceMethods
    include Associations
  end

  module ClassMethods
    def _dag_options
      TypedDag::Configuration[self]
    end
  end

  module InstanceMethods
    def _dag_options
      self.class._dag_options
    end

    def direct_edge?
      _dag_options.type_columns.one? { |type_column| send(type_column) == 1 }
    end

    private

    def add_closures
      return unless direct_edge?

      self.class.connection.execute add_dag_closure_sql
    end

    def truncate_closures
      return unless direct_edge?

      self.class.connection.execute truncate_dag_closure_sql
    end

    def add_dag_closure_sql
      TypedDag::Sql::AddClosure.sql(self)
    end

    def truncate_dag_closure_sql
      TypedDag::Sql::TruncateClosure.sql(self)
    end

    def ancestor_id_value
      send(_dag_options.ancestor_column)
    end

    def descendant_id_value
      send(_dag_options.descendant_column)
    end
  end

  module Associations
    extend ActiveSupport::Concern

    included do
      after_create :add_closures
      after_destroy :truncate_closures

      validates_uniqueness_of :ancestor,
                              scope: [:descendant],
                              conditions: -> {
                                where.not("#{_dag_options.type_columns.join(' + ')} > 1")
                              }

      belongs_to :ancestor,
                 class_name: _dag_options.node_class_name,
                 foreign_key: _dag_options.ancestor_column
      belongs_to :descendant,
                 class_name: _dag_options.node_class_name,
                 foreign_key: _dag_options.descendant_column

      validate :no_circular_dependency

      def self.with_type_columns_not(column_requirements)
        where
          .not(column_requirements)
          .with_type_colums_0(_dag_options.type_columns - column_requirements.keys)
      end

      def self.with_type_columns(column_requirements)
        where(column_requirements)
          .with_type_colums_0(_dag_options.type_columns - column_requirements.keys)
      end

      def self.with_type_colums_0(columns)
        requirements = columns.map { |column| [column, 0] }.to_h

        where(requirements)
      end

      def self.of_ancestor_and_descendant(ancestor, descendant)
        where(_dag_options.ancestor_column => ancestor,
              _dag_options.descendant_column => descendant)
      end

      private

      def no_circular_dependency
        if self.class.of_ancestor_and_descendant(send(_dag_options.descendant_column),
                                                 send(_dag_options.ancestor_column)).exists?
          errors.add :base, :'typed_dag.circular_dependency'
        end
      end
    end
  end
end
