module DataBuilder
  # Builder wizard templates: opaque JSON state snapshots.
  class TemplatesController < ApplicationController
    # GET /templates - list without state, which can be large
    def index
      templates = Template.order(:name).map do |t|
        { name: t.name, description: t.description, savedAt: t.updated_at.iso8601 }
      end
      render json: { templates: templates }
    end

    # GET /templates/:name
    def show
      template = find_template or return
      render json: { name: template.name, description: template.description,
                     savedAt: template.updated_at.iso8601, state: JSON.parse(template.state) }
    end

    # PUT /templates/:name - create or update
    def update
      return send_message(400, "invalid template name") unless valid_id?(params[:name])
      state = params[:state]
      state = state.to_unsafe_h if state.respond_to?(:to_unsafe_h)
      return send_message(400, "missing template state") if state.nil?

      template = Template.find_or_initialize_by(name: params[:name])
      template.description = params[:description].presence
      template.state = JSON.generate(state)
      template.save!
      render json: { message: "template '#{template.name}' saved" }
    end

    # DELETE /templates/:name
    def destroy
      template = find_template or return
      template.destroy!
      render json: { message: "template '#{template.name}' deleted" }
    end

    private

    def find_template
      return send_message(400, "invalid template name") && nil unless valid_id?(params[:name])
      template = Template.find_by(name: params[:name])
      send_message(404, "template '#{params[:name]}' not found") unless template
      template
    end
  end
end
