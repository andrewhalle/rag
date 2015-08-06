require 'json'
require 'date'
require 'active_support'
require 'active_support/all' # lazy loading so this should be OK.
require 'mechanize'
require_relative 'base'


module Assignment
  # convenience mixin for managing submission times and point scalings
  module TimeBracket
    attr_accessor :point_scaling
    def self.create_time_bracket(time_string, scaling)
      time = Time.parse(time_string).extend(TimeBracket)
      time.point_scaling = scaling
      time
    end
  end

  # this class contains both the assignment info extracted from grader_payload
  # as well as the submission itself. Any adapter should be able to grade this
  # type of submission and return a response.
  class Xqueue < Base
    def initialize(submission)
      grader_payload = submission.grader_payload
      @assignment_name = grader_payload['assignment_name']
      @assignment_spec_file = fetch_spec_file(grader_payload['assignment_spec_uri'])
      @autograder_type = grader_payload['autograder_type']
      @due_dates = grader_payload['due_dates'].map {|key, value| TimeBracket.create_time_bracket(key, value)}.sort
    end

    def apply_lateness!(submission)
      submission_time = submission.submission_time
      submit_range = @due_dates.map {|due_date| submission_time < due_date}.find_index(true) #return index of which date range submission falls into. if nil,
      grade_scale = submit_range ? @due_dates[submit_range].point_scaling : 0
      submission.score = grade_scale * submission.score
      submission.message = "Your submission was recorded at #{submission_time}:" +
                           ( (grade_scale == 1.0) ?  'submission is on time.' :
                            "submission is late and scaled by #{grade_scale}" )
      submission
    end

    protected
    # Get the spec file from grader payload download URI unless it already exists. Returns a file path, which is either a file or a directory containing spec files to run.
    def fetch_spec_file(spec_uri)
      file_path = "#{ENV['BASE_FOLDER']}#{@assignment_name}-spec"
      if not File.exist? file_path
        if spec_uri.include? '.git'  # lazy way of getting a git URI
          if system("git clone #{spec_uri} temp_repo")
            spec_from_repo('temp_repo/autograder', file_path)
          else
            raise IOError.new("Fatal error: Retrieving spec files from #{spec_uri} repository failed.")
          end
        else
          session = Mechanize.new
          File.open(file_path, 'w') { |f| f.write(session.get(spec_uri).body); f}
        end
      end
      file_path
    end

    def spec_from_repo(repo_path, dest_path)
      FileUtils.cp_r(repo_path, dest_path)
      FileUtils.rm_rf('temp_repo')
    end
  end
end
