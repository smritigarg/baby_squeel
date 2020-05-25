require 'spec_helper'

describe '#joining' do
  context 'when joining explicitly' do
    it 'inner joins' do
      relation = Post.joining {
        author.on(author.id == author_id)
      }

      # binding.pry
      expect(relation).to match_sql_snapshot
    end

    it 'inner joins explicitly' do
      relation = Post.joining {
        author.inner.on(author.id == author_id)
      }

      expect(relation).to match_sql_snapshot
    end

    it 'inner joins explicitly with alias' do
      relation = Post.joining { |post|
        post.author.as('a').on { id == post.author_id }
      }

      expect(relation).to match_sql_snapshot
    end

    it 'outer joins' do
      relation = Post.joining {
        author.outer.on(author.id == author_id)
      }

      expect(relation).to match_sql_snapshot
    end

    it 'self joins' do
      relation = Post.joining { on(id == 1) }

      expect(relation).to match_sql_snapshot
    end

    it 'self outer joins' do
      relation = Post.joining { outer.on(id == 1) }

      expect(relation).to match_sql_snapshot
    end

    it 'self joins with alias' do
      relation = Post.joining {
        on(id == 1).alias('meatloaf')
      }

      expect(relation).to match_sql_snapshot
    end

    it 'aliases' do
      relation = Post.joining {
        author.alias('a').on(author.id == author_id)
      }

      expect(relation).to match_sql_snapshot
    end

    it 'aliases after the on clause' do
      relation = Post.joining {
        author.on(author.id == author_id).alias('a')
      }

      expect(relation).to match_sql_snapshot
    end

    it 'merges bind values' do
      relation = Post.joining { ugly_author_comments }

      expect(relation).to match_sql_snapshot
    end

    context 'with complex conditions' do
      it 'inner joins' do
        relation = Post.joining {
          author.on(
            (author_id == author.id) & (author.id != 5) | (author.name == nil)
          )
        }

        expect(relation).to match_sql_snapshot
      end

      it 'outer joins' do
        relation = Post.joining {
          author.outer.on(
            (author_id == author.id) & (author.id != 5) | (author.name == nil)
          )
        }

        expect(relation).to match_sql_snapshot
      end
    end
  end

  context 'when joining implicitly' do
    it 'inner joins' do
      relation = Post.joining { author }
      expect(relation).to produce_sql(Post.joins(:author))
    end

    it 'outer joins' do
      relation = Post.joining { author.outer }

      expect(relation).to match_sql_snapshot
    end

    it 'correctly aliases when joining the same table twice' do
      relation = Post.joining { [author.outer, parent.outer.author.outer] }
      relation = relation.where.has do
        (author.outer.name == 'Rick') | (parent.outer.author.outer.name == 'Flair')
      end

      expect(relation).to match_sql_snapshot
    end

    describe 'polymorphism' do
      it 'inner joins' do
        if ActiveRecord::VERSION::STRING >= '5.2.0'
          pending "polyamorous's support for polymorphism is broken"
        end

        relation = Picture.joining { imageable.of(Post) }

        expect(relation).to match_sql_snapshot
      end

      it 'outer joins' do
        if ActiveRecord::VERSION::STRING >= '5.2.0'
          pending "polyamorous's support for polymorphism is broken"
        end

        relation = Picture.joining { imageable.of(Post).outer }

        expect(relation).to match_sql_snapshot
      end
    end

    describe 'habtm' do
      it 'inner joins' do
        relation = ResearchPaper.joins(:authors).where.has { authors.name == "Alex" }

        expect(relation).to match_sql_snapshot
      end
    end

    describe 'nested joins' do
      it 'inner joins' do
        relation = Post.joining { author.comments }

        expect(relation).to match_sql_snapshot
      end

      it 'outer joins' do
        relation = Post.joining { author.outer.comments }

        expect(relation).to match_sql_snapshot
      end

      it 'handles polymorphism' do
        if ActiveRecord::VERSION::STRING >= '5.2.0'
          pending "polyamorous's support for polymorphism is broken"
        end

        relation = Picture.joining { imageable.of(Post).comments }

        expect(relation).to match_sql_snapshot
      end

      it 'outer joins at multiple levels' do
        relation = Post.joining { author.outer.comments.outer }

        expect(relation).to match_sql_snapshot
      end

      it 'outer joins only the specified associations' do
        relation = Post.joining { author.comments.outer }

        expect(relation).to match_sql_snapshot
      end

      it 'joins back with a new alias' do
        baby_squeel = Post.joining { author.posts }
        active_record = Post.joins(author: :posts)
        expect(baby_squeel).to produce_sql(active_record)
      end

      it 'prevents mutation of the original instance' do
        relation = Post.joining {
          author.posts # this should have absolutely no effect
          author
        }

        expect(relation).to produce_sql(Post.joins(:author))
      end

      it 'joins a through association' do
        baby_squeel = Post.joining { author.posts.author_comments }
        active_record = Post.joins(author: { posts: :author_comments})
        expect(baby_squeel).to produce_sql(active_record)
      end

      it 'joins a through association and then back again' do
        relation = Post.joining { author.posts.author_comments.outer.post.author_comments }

        expect(relation).to match_sql_snapshot
      end
    end

    describe 'duplicate prevention' do
      context 'when given two DSL joins' do
        it 'dedupes' do
          relation = Post.joining { author }.joining { author }
          expect(relation).to produce_sql(Post.joins(:author))
        end

        it 'dedupes incremental joins' do
          relation = Post.joining { author }.joining { author.posts }

          expect(relation).to match_sql_snapshot
        end
      end

      context 'when given a DSL join with an Active Record join' do
        it 'dedupes' do
          relation = Post.joining { author }.joins(:author)
          expect(relation).to produce_sql(Post.joins(:author))
        end

        it 'dedupes (in any order)' do
          relation = Post.joins(:author).joining { author }
          expect(relation).to produce_sql(Post.joins(:author))
        end

        it 'dedupes through joins' do
          relation = Post.joins(author: { posts: :author_comments })
                         .joining { author.posts.author_comments.outer }

          # There are duplicate inner joins in here, but that'll have to do...
          expect(relation).to match_sql_snapshot
        end

        it 'dedupes incremental outer joins' do
          relation = Post.joins(:author).joining { author.comments.outer }

          expect(relation).to match_sql_snapshot
        end

        it 'dedupes incremental outer joins (in any order)' do
          relation = Post.joining { author.comments.outer }.joins(:author)

          expect(relation).to match_sql_snapshot
        end
      end

      context 'when given a DSL join with an Arel join' do
        let(:arel_join) {
          Arel::Nodes::InnerJoin.new(
            Author.arel_table,
            Arel::Nodes::On.new(
              Post.arel_table[:author_id].eq(
                Author.arel_table[:id]
              )
            )
          )
        }

        it 'does what Active Record would do' do
          baby_squeel = Post.joining { author }.joins(arel_join)
          active_record = Post.joins(:author).joins(arel_join)
          expect(baby_squeel).to produce_sql(active_record)
        end

        it 'does what Active Record would do (in any order)' do
          baby_squeel = Post.joins(arel_join).joining { author }
          active_record = Post.joins(arel_join).joins(:author)
          expect(baby_squeel).to produce_sql(active_record)
        end
      end
    end

    it 'raises an error when attempting to alias an inner join' do
      expect {
        Post.joining { author.alias('a') }.to_sql
      }.to raise_error(BabySqueel::AssociationAliasingError, /'author' as 'a'/)
    end

    it 'raises an error when attempting to alias an outer join' do
      expect {
        Post.joining { author.outer.alias('a') }.to_sql
      }.to raise_error(BabySqueel::AssociationAliasingError, /'author' as 'a'/)
    end
  end
end
