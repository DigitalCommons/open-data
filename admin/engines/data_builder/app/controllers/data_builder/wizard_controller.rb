module DataBuilder
  class WizardController < ApplicationController
    # GET / - the builder wizard (a self-contained page, no host layout)
    def show
      render layout: false
    end
  end
end
