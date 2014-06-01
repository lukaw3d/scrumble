'use strict'

angular.module('scrumbleApp')
  .controller 'ProductCtrl', ($scope, $rootScope, $modal, Story, Project, ProjectUser, Sprint, SprintStory, Task, growl) ->
    projectId = $rootScope.currentUser.activeProject

    ProjectUser.get projectId: projectId, userId: $rootScope.currentUser.id, (projectUser) ->
      $scope.isProductOwner = 'ProductOwner' in projectUser.roles
      $scope.isScrumMaster = 'ScrumMaster' in projectUser.roles

    $scope.load = ->
      $scope.sprints = Sprint.query projectId: projectId, (sprints) ->
        $scope.currentSprint = _.find sprints, (x) -> x.current

        $scope.stories = Story.query projectId: projectId, ->
          $scope.finishedStories = $scope.filterDone($scope.stories)
          $scope.unfinishedStories = $scope.filterNotDone($scope.stories)
          $scope.unfinishedCurrentStories = _.filter $scope.unfinishedStories, (x) -> x.sprint == $scope.currentSprint
          $scope.unfinishedRemainingStories = _.filter $scope.unfinishedStories, (x) -> x.sprint != $scope.currentSprint

          _.each $scope.unfinishedCurrentStories, (story) ->
            Task.query {projectId: projectId, sprintId: $scope.currentSprint.id, storyId: story.id}, (tasks) ->
              story.tasks = tasks
            , (reason) ->
              growl.addErrorMessage($scope.$root.backupError(reason.data.message, "An error occured while loading tasks"))
    $scope.load()

    $scope.canAddStory = ->
      $scope.isProductOwner || $scope.isScrumMaster

    $scope.addOrEditStory = (story) ->
      modalInstance = $modal.open(
        templateUrl: 'views/product-story-add-modal.html'
        controller: 'ProductStoryAddModalCtrl'
        resolve:
          story: -> story
      )
      modalInstance.result.then ->
        $scope.load()

    $scope.canEditStoryEstimate = (story) ->
      not story.done and not story.sprint and $scope.isScrumMaster

    $scope.changeStoryEstimate = (story) ->
      modalInstance = $modal.open(
        templateUrl: 'views/product-story-estimate-modal.html'
        controller: 'ProductStoryEstimateModalCtrl'
        resolve:
          story: -> story
      )
      modalInstance.result.then ->
        story.$update
          projectId: projectId
          storyId: story.id
        , $scope.load

    $scope.canAddUnfinishedStoryToSprint = (story) ->
      not story.sprint and $scope.isScrumMaster and story.points? and story.points > 0

    $scope.canRemoveUnfinishedStoryFromSprint = (story) ->
      no
      # story.sprint and $scope.isScrumMaster

    $scope.canAddFinishedStoryToSprint = (story) ->
      no

    $scope.canRemoveFinishedStoryFromSprint = (story) ->
      no

    $scope.addStoryToSprint = (story) ->
      sprintStory = new SprintStory()
      sprintStory.$update
        projectId: projectId
        sprintId: $scope.currentSprint.id
        storyId: story.id
      , $scope.load

    $scope.removeStoryFromSprint = (story) ->
      sprintStory = new SprintStory()
      sprintStory.$delete
        projectId: projectId
        sprintId: story.sprint.id
        storyId: story.id
      , $scope.load

  .directive('productStory', ->
    restrict: 'E'
    scope:
      story: '='
      currentSprint: '='
      canAddToSprint: '='
      addToSprint: '='
      canRemoveFromSprint: '='
      removeFromSprint: '='
      canEditEstimate: '='
      changeEstimate: '='
      canAcceptReject: '='
      load: '='
      defaultClass: '@'
      canEditStory: '='
      editStory: '='
    replace: yes
    templateUrl: 'views/product-story.html'
    controller: ($scope, $filter, $rootScope, $modal, $q, Sprint, Story, SprintStory, Task, User, growl, bbox) ->

      projectId = $scope.$root.currentUser.activeProject
      $scope.storyIsCompleted = (story) ->
        story.tasks? and story.tasks.length > 0 and _.all story.tasks, (task) -> task.status == 'Completed'
      $scope.acceptStory = (story) ->
        storyStory = new Story()
        story.done = true
        angular.extend storyStory, story
        storyStory.sprint = storyStory.sprint.id
        storyStory.points = 1 if !storyStory.points
        storyStory.$update
          projectId: projectId
          storyId: storyStory.id
        , ->
          $scope.load()
        , (reason) ->
          growl.addErrorMessage($scope.$root.backupError(reason.data.message, "An error occured while accepting a story"))
          $scope.load()
      $scope.rejectStory = (story) ->
        bbox.prompt 'Add a note?', (note) ->
          promises = []
          if note
            story.notes.push(note)

            storyStory = new Story()
            angular.extend storyStory, story
            storyStory.sprint = storyStory.sprint.id
            promises.push storyStory.$update
              projectId: projectId
              storyId: storyStory.id

          sprintStory = new SprintStory()
          promises.push sprintStory.$delete
            projectId: projectId
            sprintId: story.sprint.id
            storyId: story.id

          $q.all(promises).then ->
            $scope.load()
          , (reason) ->
            growl.addErrorMessage($scope.$root.backupError(reason.data.message, "An error occured while rejecting a story"))
            $scope.load()
  )

  .controller 'ProductStoryAddModalCtrl', ($scope, $rootScope, $modalInstance, Story, growl, story) ->
    projectId = $rootScope.currentUser.activeProject

    if !story
      $scope.story = new Story
      $scope.story.tests = [{test: ''}]
      $scope.story.notes = [{notes: ''}]
      $scope.story.priority = 'MustHave'
      $scope.story.businessValue = 0
      $scope.story.project = projectId
    else
      $scope.story = angular.copy story
      $scope.story.tests = [''] unless $scope.story.tests?.length > 0
      $scope.story.notes = [''] unless $scope.story.notes?.length > 0
      $scope.story.tests = _.map $scope.story.tests, (t) -> test: t
      $scope.story.notes = _.map $scope.story.notes, (t) -> note: t

    $scope.autoError = {}
    $scope.addTest = ->
      $scope.story.tests.push({test: ''})
    $scope.addNote = ->
      $scope.story.notes.push({note: ''})

    $scope.submitStory = (invalid) ->
      if !$scope.story.id?
        $scope.addStory(invalid)
      else
        $scope.updateStory(invalid)

    $scope.addStory = (invalid) ->
      if (invalid)
        return
      s = new Story()
      s.description = ''
      angular.extend(s, $scope.story)
      s.tests = _.filter(_.map $scope.story.tests, (t) -> t.test)
      s.notes = _.filter(_.map $scope.story.notes, (t) -> t.note)

      s.$save projectId: projectId, ->
        $modalInstance.close()

        growl.addSuccessMessage("Story has been added.")
        $scope.autoError.removeErrors()
      , (reason) ->
        growl.addErrorMessage($scope.$root.backupError(reason.data.message, "An error occured while adding story"))
        $scope.autoError.showErrors(reason.data)

    $scope.updateStory = (invalid) ->
      if (invalid)
        return
      s = new Story()
      s.description = ''
      angular.extend(s, $scope.story)
      s.tests = _.filter(_.map $scope.story.tests, (t) -> t.test)
      s.notes = _.filter(_.map $scope.story.notes, (t) -> t.note)

      s.$update
        projectId: projectId
        storyId: s.id
      , ->
        $modalInstance.close()

        growl.addSuccessMessage("Story has been changed.")
        $scope.autoError.removeErrors()
      , (reason) ->
        growl.addErrorMessage($scope.$root.backupError(reason.data.message, "An error occured while changing story"))
        $scope.autoError.showErrors(reason.data)

    $scope.deleteStory = ->
      $scope.story.$delete
        projectId: projectId
        storyId: $scope.story.id
      , ->
        $modalInstance.close()
        growl.addSuccessMessage("Story has been deleted.")
      , (reason) ->
        growl.addErrorMessage($scope.$root.backupError(reason.data.message, "An error occured while deleting story"))

    $scope.cancel = ->
      $modalInstance.dismiss()


  .controller 'ProductStoryEstimateModalCtrl', ($scope, $rootScope, $modalInstance, Story, growl, story) ->
    $scope.story = story

    $scope.estimate =
      points: story.points || 0

    $scope.save = (invalid) ->
      return if invalid

      $scope.story.points = $scope.estimate.points

      $modalInstance.close()

    $scope.cancel = ->
      $modalInstance.dismiss()
