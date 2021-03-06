require 'rails_helper'

describe EmbedController do

  let(:host) { "eviltrout.com" }
  let(:embed_url) { "http://eviltrout.com/2013/02/10/why-discourse-uses-emberjs.html" }
  let(:discourse_username) { "eviltrout" }

  it "is 404 without an embed_url" do
    get :comments
    expect(response).to render_template :embed_error
  end

  it "raises an error with a missing host" do
    get :comments, embed_url: embed_url
    expect(response).to render_template :embed_error
  end

  context "by topic id" do

    before do
      Fabricate(:embeddable_host)
      controller.request.stubs(:referer).returns('http://eviltrout.com/some-page')
    end

    it "allows a topic to be embedded by id" do
      topic = Fabricate(:topic)
      get :comments, topic_id: topic.id
      expect(response).to be_success
    end
  end

  context ".info" do
    context "without api key" do
      it "fails" do
        get :info, format: :json
        expect(response).to render_template :embed_error
      end
    end

    context "with api key" do

      let(:api_key) { ApiKey.create_master_key }

      context "with valid embed url" do
        let(:topic_embed) { Fabricate(:topic_embed, embed_url: embed_url) }

        it "returns information about the topic" do
          get :info, format: :json, embed_url: topic_embed.embed_url, api_key: api_key.key, api_username: "system"
          json = JSON.parse(response.body)
          expect(json['topic_id']).to eq(topic_embed.topic.id)
          expect(json['post_id']).to eq(topic_embed.post.id)
          expect(json['topic_slug']).to eq(topic_embed.topic.slug)
        end
      end

      context "without invalid embed url" do
        it "returns error response" do
          get :info, format: :json, embed_url: "http://nope.com", api_key: api_key.key, api_username: "system"
          json = JSON.parse(response.body)
          expect(json["error_type"]).to eq("not_found")
        end
      end
    end
  end

  context "with a host" do
    let!(:embeddable_host) { Fabricate(:embeddable_host) }

    it "raises an error with no referer" do
      get :comments, embed_url: embed_url
      expect(response).to render_template :embed_error
    end

    context "success" do
      before do
        controller.request.stubs(:referer).returns(embed_url)
      end

      after do
        expect(response).to be_success
        expect(response.headers['X-Frame-Options']).to eq("ALLOWALL")
      end

      it "tells the topic retriever to work when no previous embed is found" do
        TopicEmbed.expects(:topic_id_for_embed).returns(nil)
        retriever = mock
        TopicRetriever.expects(:new).returns(retriever)
        retriever.expects(:retrieve)
        get :comments, embed_url: embed_url
      end

      it "creates a topic view when a topic_id is found" do
        TopicEmbed.expects(:topic_id_for_embed).returns(123)
        TopicView.expects(:new).with(123, nil, limit: 100, exclude_first: true, exclude_deleted_users: true, exclude_hidden: true)
        get :comments, embed_url: embed_url
      end

      it "provides the topic retriever with the discourse username when provided" do
        TopicRetriever.expects(:new).with(embed_url, has_entry(author_username: discourse_username))
        get :comments, embed_url: embed_url, discourse_username: discourse_username
      end

    end
  end

  context "with multiple hosts" do
    before do
      Fabricate(:embeddable_host)
      Fabricate(:embeddable_host, host: 'http://discourse.org')
      Fabricate(:embeddable_host, host: 'https://example.com/1234', class_name: 'example')
    end

    context "success" do
      it "works with the first host" do
        controller.request.stubs(:referer).returns("http://eviltrout.com/wat/1-2-3.html")
        get :comments, embed_url: embed_url
        expect(response).to be_success
      end

      it "works with the second host" do
        controller.request.stubs(:referer).returns("https://discourse.org/blog-entry-1")
        get :comments, embed_url: embed_url
        expect(response).to be_success
      end

      it "works with a host with a path" do
        controller.request.stubs(:referer).returns("https://example.com/some-other-path")
        get :comments, embed_url: embed_url
        expect(response).to be_success
      end

      it "contains custom class name" do
        controller.request.stubs(:referer).returns("https://example.com/some-other-path")
        get :comments, embed_url: embed_url
        expect(assigns(:embeddable_css_class)).to eq(' class="example"')
      end

      it "doesn't work with a made up host" do
        controller.request.stubs(:referer).returns("http://codinghorror.com/invalid-url")
        get :comments, embed_url: embed_url
        expect(response).to render_template :embed_error
      end
    end
  end
end
