## Process-isolated import probe for the complete public façade.
import terminal_status

static:
  doAssert compiles(block:
    var
      statusState: StatusState
      progressMode: ProgressMode
      statusError: ref StatusError
      statusStateError: ref StatusStateError
      unknownTaskError: ref UnknownTaskError
      taskIdExhaustedError: ref TaskIdExhaustedError
      taskId: TaskId
      progressSnapshot: ProgressTaskSnapshot
      stepSnapshot: StepSnapshot
      spinnerStyle: SpinnerStyle
      spinner: Spinner
      progress: ProgressBar
      multi: MultiProgress
      tracker: StepTracker
      characters: StatusCharacters
      markers: StatusMarkers
      theme: StatusTheme
      renderOptions: RenderOptions
      liveMode: LiveMode
      plainPolicy: PlainOutputPolicy
      finishPolicy: FinishPolicy
      liveState: LiveDisplayState
      liveError: ref LiveDisplayError
      liveOptions: LiveDisplayOptions
      display: LiveDisplay
    discard statusState
    discard progressMode
    discard statusError
    discard statusStateError
    discard unknownTaskError
    discard taskIdExhaustedError
    discard taskId
    discard progressSnapshot
    discard stepSnapshot
    discard spinnerStyle
    discard spinner
    discard progress
    discard multi
    discard tracker
    discard characters
    discard markers
    discard theme
    discard renderOptions
    discard liveMode
    discard plainPolicy
    discard finishPolicy
    discard liveState
    discard liveError
    discard liveOptions
    discard display
  )
  doAssert compiles(initSpinner("facade export probe").render())
  doAssert compiles(initProgressBar("facade export probe", 1).render())
  doAssert compiles(initStepTracker(["facade export probe"]).render())
  doAssert compiles(block:
    var liveDisplay = initLiveDisplay()
    liveDisplay.open()
  )
