# app/controllers/api/v1/review_mappings_controller.rb

module Api
  module V1
    class ReviewMappingsController < ApplicationController
        # Set up before actions for common operations
      include ReviewMappingsHelper

      before_action :authorize_request
      before_action :set_review_mapping, only: [:show, :update, :destroy]
        before_action :validate_contributor_id, only: [:select_reviewer]

      # GET /api/v1/review_mappings
        # Returns a list of all review mappings
      def index
        render json: { message: "Use /assignments/:assignment_id/review_mappings to list mappings." }, status: :ok
      end

      # GET /api/v1/assignments/:assignment_id/review_mappings
      # This action fetches all review mappings associated with a specific assignment.
      # Optional query parameters (reviewer_id, reviewee_id, type) can be used to filter the results.
      def list_mappings
        # Whitelist and extract the relevant query parameters
        params.permit(:assignment_id, :reviewer_id, :reviewee_id, :type)

        # Find the assignment by the provided assignment_id
        assignment = Assignment.find_by(id: params[:assignment_id])

        # Return 404 Not Found if the assignment doesn't exist
        if assignment.nil?
          render json: { error: 'Assignment not found' }, status: :not_found
          return
        end

        # Extract optional filtering parameters
        filters = params.slice(:reviewer_id, :reviewee_id, :type)

        # Fetch the review mappings using the helper method with the given filters
        mappings_data = fetch_review_mappings(assignment, filters)

        # Respond with the filtered review mappings in JSON format
        render json: mappings_data, status: :ok
      end


      # GET /api/v1/review_mappings/:id
        # Returns a specific review mapping by ID
      def show
        render json: @review_mapping
      end

      # POST /api/v1/review_mappings
        # Creates a new review mapping
      def create
        @review_mapping = ReviewMapping.new(review_mapping_params)

        if @review_mapping.save
          render json: @review_mapping, status: :created
        else
          render json: @review_mapping.errors, status: :unprocessable_entity
        end
      end

      # PATCH/PUT /api/v1/review_mappings/:id
      def update
        if @review_mapping.update(review_mapping_params)
          render json: @review_mapping
        else
          render json: @review_mapping.errors, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/review_mappings/:id
      def destroy
        @review_mapping.destroy
        head :no_content
      end

  
        # POST /api/v1/review_mappings/add_calibration
        # Creates a calibration review mapping between a team and an assignment
        # This is used for calibration reviews where instructors review team submissions
        # to establish grading standards
        def add_calibration
          result = ReviewMapping.create_calibration_review(
            assignment_id: params.dig(:calibration, :assignment_id),
            team_id: params.dig(:calibration, :team_id),
            user_id: current_user.id
          )
  
          if result.success
            render json: result.review_mapping, status: :created
          else
            render json: { error: result.error }, status: :unprocessable_entity
          end
        end
  
        # GET /api/v1/review_mappings/select_reviewer
        # Selects a contributor for review mapping and stores it in the session
        # This is used in the review assignment process to track the selected contributor
        def select_reviewer
          @contributor = Team.find(params[:contributor_id])
          session[:contributor] = @contributor
          render json: @contributor, status: :ok
        rescue ActiveRecord::RecordNotFound
          render json: { error: "Contributor not found" }, status: :not_found
        end
  
        # POST /api/v1/review_mappings/add_reviewer
        # Adds a reviewer to a review mapping
        # This endpoint handles the assignment of reviewers to teams for review purposes
        def add_reviewer
          Rails.logger.debug "Raw params: #{params.inspect}"
          Rails.logger.debug "Request content type: #{request.content_type}"
          Rails.logger.debug "Request body: #{request.body.read}"
          
          begin
            result = ReviewMapping.add_reviewer(
              assignment_id: params[:id],
              team_id: params[:contributor_id],
              user_name: params.dig(:user, :name)
            )
  
            if result.success?
              render json: result.review_mapping, status: :created
            else
              render json: { error: result.error }, status: :unprocessable_entity
            end
          rescue => e
            Rails.logger.error "Error in add_reviewer: #{e.message}"
            Rails.logger.error e.backtrace.join("\n")
            render json: { error: e.message }, status: :bad_request
          end
        end
  
        # POST /api/v1/review_mappings/assign_reviewer_dynamically
        # Assigns a reviewer dynamically to a team or topic
        def assign_reviewer_dynamically
          result = ReviewMapping.assign_reviewer_dynamically(
            assignment_id: params[:assignment_id],
            reviewer_id: params[:reviewer_id],
            topic_id: params[:topic_id],
            i_dont_care: params[:i_dont_care].present?
          )
  
          if result.success?
            render json: result.review_mapping, status: :created
          else
            render json: { error: result.error }, status: :unprocessable_entity
          end
        end
          
        # GET /api/v1/review_mappings/review_allowed
        # Checks if a reviewer can perform more reviews for an assignment
        def review_allowed
          result = ReviewResponseMap.review_allowed?(params[:assignment_id], params[:reviewer_id])

          if result.success
            render plain: result.allowed.to_s
          else
            render json: { error: result.error }, status: :unprocessable_entity
          end
        end
  
        # GET /api/v1/review_mappings/check_outstanding_reviews
        # Checks if a reviewer has exceeded the maximum number of outstanding reviews
        def check_outstanding_reviews
          result = ReviewMapping.check_outstanding_reviews?(
            Assignment.find(params[:assignment_id]),
            User.find(params[:reviewer_id])
          )

          if result.success
            render plain: result.allowed.to_s
          else
            render json: { error: result.error }, status: :unprocessable_entity
          end
        rescue ActiveRecord::RecordNotFound
          render json: { error: "Assignment or Reviewer not found" }, status: :unprocessable_entity
        end
  
        # POST /api/v1/review_mappings/assign_quiz_dynamically
        # Assigns a quiz to a participant for a specific assignment
        def assign_quiz_dynamically
          result = QuizResponseMap.assign_quiz(
            assignment_id: params[:assignment_id],
            reviewer_id: params[:reviewer_id],
            questionnaire_id: params[:questionnaire_id]
          )

          if result.success
            render json: result.quiz_response_map, status: :created
          else
            render json: { error: result.error }, status: :unprocessable_entity
          end
        end
  
        # POST /api/v1/review_mappings/start_self_review
        # Initiates a self-review process for a participant
        def start_self_review
          Rails.logger.debug "Starting self-review with params: #{params.inspect}"
          
          result = SelfReviewResponseMap.create_self_review(
            assignment_id: params[:assignment_id],
            reviewer_id: params[:reviewer_id],
            reviewer_userid: params[:reviewer_userid]
          )

          Rails.logger.debug "Self-review result: #{result.inspect}"
          
          if result.success
            render json: result.self_review_map, status: :created
          else
            error_message = result.error || "Unknown error occurred during self-review creation"
            Rails.logger.error "Self-review error: #{error_message}"
            render json: { error: error_message }, status: :unprocessable_entity
          end
        rescue => e
          Rails.logger.error "Exception in start_self_review: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
          render json: { error: e.message }, status: :unprocessable_entity
        end
  
        # GET /api/v1/review_mappings/get_questionnaire_id
        # Returns the questionnaire ID for a given assignment and reviewer
        def get_questionnaire_id
          assignment = Assignment.find(params[:assignment_id])
          reviewer = User.find(params[:reviewer_id])

          # Get the review questionnaire for the assignment
          questionnaire = assignment.review_questionnaire_id

          if questionnaire
            render json: { questionnaire_id: questionnaire.id }, status: :ok
          else
            render json: { error: "No questionnaire found for this assignment" }, status: :not_found
          end
        rescue ActiveRecord::RecordNotFound
          render json: { error: "Assignment or Reviewer not found" }, status: :not_found
        end

      # POST /api/v1/assignments/:assignment_id/automatic_review_mapping
      # Automatically generates reviewer-reviewee mappings for a given assignment.
      def automatic_review_mapping
        # Permit only the expected parameters from the request
        params.permit(:assignment_id, :num_reviews_per_student, :num_of_reviewers, :strategy)

        # Find the assignment using the provided assignment_id
        assignment = Assignment.find_by(id: params[:assignment_id])

        # Return a 404 error if the assignment does not exist
        if assignment.nil?
          render json: { error: 'Assignment not found' }, status: :not_found
          return
        end

        # Delegate the mapping generation logic to the helper function
        result = generate_automatic_review_mappings(assignment, params)

        # If successful, return a success message with status 200
        if result[:success]
          render json: { message: result[:message] }, status: :ok
        else
          # If mapping fails, return an error message with status 422
          render json: { error: result[:message] }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/assignments/:assignment_id/automatic_review_mapping_strategy
      def automatic_review_mapping_strategy
        # Allow only the permitted parameters from the incoming request.
        # These include the assignment ID (from the URL), number of reviews per student, and the desired strategy.
        params.permit(:assignment_id, :num_reviews_per_student, :strategy)

        # Attempt to find the Assignment record based on the provided assignment_id.
        # If no such assignment exists, respond with a 404 Not Found error.
        assignment = Assignment.find_by(id: params[:assignment_id])
        if assignment.nil?
          render json: { error: 'Assignment not found' }, status: :not_found
          return
        end

        # Pass control to the helper method responsible for generating review mappings
        # using the specified strategy. The helper handles logic variations based on the strategy value.
        result = generate_review_mappings_with_strategy(assignment, params)

        # Check the result returned by the helper method.
        # If successful, return a success message with HTTP 200 OK.
        if result[:success]
          render json: { message: result[:message] }, status: :ok
        else
          render json: { error: result[:message] }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/assignments/:assignment_id/automatic_review_mapping_staggered
      def automatic_review_mapping_staggered
        # Permit only the required params for safety
        params.permit(:assignment_id, :num_reviews_per_student, :strategy)

        # Find the assignment by ID
        assignment = Assignment.find_by(id: params[:assignment_id])
        if assignment.nil?
          render json: { error: 'Assignment not found' }, status: :not_found
          return
        end

        # Delegate to helper that supports both individual and team-based strategies
        result = generate_staggered_review_mappings(assignment, params)

        # Render based on success/failure
        if result[:success]
          render json: { message: result[:message] }, status: :ok
        else
          render json: { error: result[:message] }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/assignments/:assignment_id/assign_reviewers_for_team
      # This endpoint assigns a fixed number of reviewers to a specific team within an assignment.
      # It supports both team-based and individual assignments.
      def assign_reviewers_for_team
        # Allow only permitted parameters from the request
        params.permit(:assignment_id, :team_id, :num_reviewers)

        # Locate the assignment using the provided ID
        assignment = Assignment.find_by(id: params[:assignment_id])
        if assignment.nil?
          # Return 404 if the assignment does not exist
          render json: { error: 'Assignment not found' }, status: :not_found
          return
        end

        # Locate the target team using the provided ID
        team = Team.find_by(id: params[:team_id])
        if team.nil?
          # Return 404 if the team is not found
          render json: { error: 'Team not found' }, status: :not_found
          return
        end

        # Set the number of reviewers, defaulting to 3 if not specified
        num_reviewers = params[:num_reviewers]&.to_i || 3

        # Delegate logic to helper method to perform the assignment
        result = assign_reviewers_for_team_logic(assignment, team, num_reviewers)

        # Return the outcome based on the helper result
        if result[:success]
          render json: { message: result[:message] }, status: :ok
        else
          render json: { error: result[:message] }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/assignments/:assignment_id/peer_review_strategy
      def peer_review_strategy
        # Permit and extract required parameters
        params.permit(:assignment_id, :num_reviews_per_student, :strategy)

        # Find the assignment by ID
        assignment = Assignment.find_by(id: params[:assignment_id])
        if assignment.nil?
          render json: { error: 'Assignment not found' }, status: :not_found
          return
        end

        # Delegate core peer review logic to helper
        result = generate_peer_review_strategy(assignment, params)

        if result[:success]
          render json: { message: result[:message] }, status: :ok
        else
          render json: { error: result[:message] }, status: :unprocessable_entity
        end
      end
      
      # Controller action to save or update a review grade and comment from a reviewer to a reviewee
      def save_grade_and_comment_for_reviewer
        # Step 1: Fetch the assignment using the assignment_id passed in params
        assignment = Assignment.find_by(id: params[:assignment_id])

        # If the assignment doesn't exist, return a 404 error
        return render json: { error: "Assignment not found." }, status: :not_found unless assignment

        # Step 2: Get the currently logged-in user (the reviewer)
        reviewer = current_user

        # Step 3: Extract the necessary parameters from the request body
        reviewee_id     = params[:reviewee_id]        # ID of the participant (or team) being reviewed
        answers         = params[:answers]            # Array of answer hashes with item_id, score, and optional comment
        overall_comment = params[:overall_comment]    # General comment for the review
        is_submitted    = params[:is_submitted]       # Boolean flag indicating if review is finalized

        # Step 4: Delegate the business logic to a helper method that handles validation and saving
        result = ReviewMappingsHelper.save_review_data(
          reviewer: reviewer,
          assignment: assignment,
          reviewee_id: reviewee_id,
          answers: answers,
          overall_comment: overall_comment,
          is_submitted: is_submitted
        )

        # Step 5: Render appropriate JSON response based on success or failure
        if result[:success]
          render json: { message: result[:message] }, status: :ok
        else
          render json: { error: result[:error] }, status: :unprocessable_entity
        end
      end


      # POST /api/v1/review_mappings/:id/select_metareviewer
      # This action assigns a metareviewer to a specific review mapping.
      def select_metareviewer
        review_mapping = ResponseMap.find_by(id: params[:id])
        return render json: { error: 'Review mapping not found' }, status: :not_found unless review_mapping
      
        metareviewer_id = params[:metareviewer_id]
        metareviewer = Participant.find_by(id: metareviewer_id)
        return render json: { error: 'Metareviewer not found' }, status: :not_found unless metareviewer
      
        # Check if metareview already exists
        existing_map = MetareviewResponseMap.find_by(reviewed_object_id: review_mapping.id, reviewer_id: metareviewer.id)
        if existing_map
          return render json: { message: 'Metareviewer already assigned' }, status: :ok
        end
      
        MetareviewResponseMap.create!(
          reviewed_object_id: review_mapping.id,
          reviewer_id: metareviewer.id,
          reviewee_id: review_mapping.reviewer_id
        )
      
        render json: { message: 'Metareviewer assigned successfully' }, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # POST /api/v1/review_mappings/:id/assign_metareviewer
      def add_metareviewer
        review_mapping = ResponseMap.find(params[:id])
        result = ReviewMappingsHelper.add_metareviewer(review_mapping)
      
        if result[:success]
          render json: { success: true, message: result[:message] }, status: :ok
        else
          render json: { success: false, message: result[:message] }, status: :unprocessable_entity
        end
      end
      
      # POST /api/v1/review_mappings/:id/assign_metareviewer_dynamically
      def assign_metareviewer_dynamically
        review_mapping = ResponseMap.find_by(id: params[:id])
        return render json: { error: 'Review mapping not found' }, status: :not_found unless review_mapping

        assignment = Assignment.find_by(id: review_mapping.reviewed_object_id)
        return render json: { error: 'Assignment not found' }, status: :not_found unless assignment

        metareviewer = ReviewMappingsHelper.find_available_metareviewer(review_mapping, assignment.id)
        return render json: { error: 'No available metareviewer found' }, status: :unprocessable_entity unless metareviewer

        MetareviewResponseMap.create!(
          reviewed_object_id: review_mapping.id,
          reviewer_id: metareviewer.id,
          reviewee_id: review_mapping.reviewer_id
        )

        render json: { message: 'Metareviewer dynamically assigned successfully', metareviewer_id: metareviewer.id }, status: :ok
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # DELETE /api/v1/review_mappings/delete_outstanding_reviewers/:assignment_id
      def delete_outstanding_reviewers
        assignment = Assignment.find_by(id: params[:assignment_id])
        return render json: { error: 'Assignment not found' }, status: :not_found unless assignment

        mappings = ReviewResponseMap.where(reviewed_object_id: assignment.id)
        deleted_count = 0

        mappings.each do |map|
          unless Response.exists?(map_id: map.id)
            map.destroy
            deleted_count += 1
          end
        end

        render json: { message: "#{deleted_count} outstanding reviewers deleted." }, status: :ok
      end

      # app/controllers/api/v1/review_mappings_controller.rb
      def delete_all_metareviewers
        assignment = Assignment.find_by(id: params[:assignment_id])
        return render json: { error: 'Assignment not found' }, status: :not_found unless assignment

        deleted_count = MetareviewResponseMap.where('reviewee_id IN (?)', Participant.where(assignment_id: assignment.id).pluck(:id)).delete_all

        render json: { message: "#{deleted_count} metareviewers deleted." }, status: :ok
      end
      
      # DELETE /api/v1/review_mappings/:id/delete_reviewer
      def delete_reviewer
        review_mapping = ResponseMap.find_by(id: params[:id])
        return render json: { error: 'Review mapping not found' }, status: :not_found unless review_mapping
      
        review_mapping.destroy
        render json: { message: 'Reviewer mapping deleted successfully' }, status: :ok
      end
      
      # DELETE /review_mappings/:id/delete_metareviewer
      def delete_metareviewer
        metareview_mapping = MetareviewResponseMap.find_by(id: params[:id])
        return render json: { error: 'Metareview mapping not found' }, status: :not_found unless metareview_mapping

        metareview_mapping.destroy
        render json: { message: 'Metareviewer mapping deleted successfully' }, status: :ok
      end

      # DELETE /review_mappings/:id/delete_metareview
      def delete_metareview
        metareview = MetareviewResponseMap.find_by(id: params[:id])
        return render json: { error: 'Metareview mapping not found' }, status: :not_found unless metareview
      
        metareview.destroy
        render json: { message: 'Metareview mapping deleted successfully' }, status: :ok
      end

      # DELETE /api/v1/review_mappings/:id/unsubmit_review
      def unsubmit_review
        review_mapping = ResponseMap.find_by(id: params[:id])
        return render json: { error: 'Review mapping not found' }, status: :not_found unless review_mapping

        response = Response.where(map_id: review_mapping.id).order(created_at: :desc).first
        return render json: { error: 'Response not found' }, status: :not_found unless response

        response.update!(is_submitted: false)
        render json: { message: 'Review unsubmitted successfully' }, status: :ok
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      

      private

        # Sets the review mapping instance variable based on the ID parameter
        # Used by show, update, and destroy actions
      def set_review_mapping
        @review_mapping = ReviewMapping.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: "ReviewMapping not found" }, status: :not_found
      end

        # Validates that a contributor_id parameter is present in the request
        # Used by the select_reviewer action
        def validate_contributor_id
          unless params[:contributor_id].present?
            render json: { error: 'Contributor ID is required' }, status: :bad_request
          end
        end
  
        # Strong parameters for review mapping creation and updates
        # Ensures only permitted attributes can be mass-assigned
      def review_mapping_params
        params.require(:review_mapping).permit(:reviewer_id, :reviewee_id, :review_type)
      end
    end
  end
end
