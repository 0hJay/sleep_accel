import WatchKit
import Foundation
import HealthKit
import CoreMotion
import WatchConnectivity

class SleepInterfaceController: WKInterfaceController, HKWorkoutSessionDelegate,URLSessionDelegate{
  
  let healthStore = HKHealthStore()
  var workoutSession : HKWorkoutSession?
  var activeDataQueries = [HKQuery]()
  var workoutStartDate : Date?
  var workoutEndDate : Date?
  var workoutEvents = [HKWorkoutEvent]()
  var metadata = [String: AnyObject]()
  var timer : Timer?
  var isPaused = false
  var counter = 0
  let threshold = 1000
  
  let motionManager = CMMotionManager()
  var allValues = "";
  let defaults = UserDefaults.standard
  var accelerometerOutput = NSMutableArray()
  var accelerometerOutputPost = NSMutableArray()

  var heartRateData: [Double] = []  
  var respiratoryRateData: [Double] = []
  var hrvData: [Double] = []
  var circadianTime: Double = 0.0

  var remTimer: Timer?
  
  var watchSession: WCSession? {
    didSet {
      if let session = watchSession {
        session.delegate = self
        session.activate()
      }
    }
  }
  
  override func awake(withContext context: Any?) {
    super.awake(withContext: context)
    watchSession = WCSession.default
    
    if let workoutConfiguration = context as? HKWorkoutConfiguration {
      do {
        workoutSession = try HKWorkoutSession(healthStore: healthStore, configuration: workoutConfiguration)
        workoutSession?.delegate = self
        workoutStartDate = Date()
        workoutSession?.startActivity(with: Date())
        
      } catch {
      }
    }
  }
  
  @IBAction func stopRecording() {
    workoutEndDate = Date()
    workoutSession?.end()
  }
  
  func pushToPhone(){
    if WCSession.isSupported() {
      
      let session = WCSession.default
      print("Attempting to post \(self.accelerometerOutputPost.count) entries to phone...")
      
      session.sendMessage(["key": Double((workoutStartDate?.timeIntervalSince1970)!), "acceleration" : self.accelerometerOutputPost], replyHandler: { (response) -> Void in
        if let response = response["response"] as? String {
          print(response)
        }
        
      }, errorHandler: { (error) -> Void in
        print(error)
      })
    }
  }
  
  func startAccumulatingData(startDate: Date) {
    startMotionCapture();
    startQuery(quantityTypeIdentifier: .heartRate)
    fetchRespiratoryRate()
    fetchLastSleepTime()

    // Use existing timer to collect respiratory rate, HRV, and check for REM
    timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { _ in
        self.fetchRespiratoryRate()
        self.calculateHRV()
        self.checkForREM()
    }

     // Separate timer for REM checking
    remTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
        self.checkForREM()
    }
  }
  
  func startQuery(quantityTypeIdentifier: HKQuantityTypeIdentifier) {
    let datePredicate = HKQuery.predicateForSamples(withStart: workoutStartDate, end: nil, options: .strictStartDate)
    let devicePredicate = HKQuery.predicateForObjects(from: [HKDevice.local()])
    let queryPredicate = NSCompoundPredicate(andPredicateWithSubpredicates:[datePredicate, devicePredicate])
    
    let updateHandler: ((HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, Error?) -> Void) = { query, samples, deletedObjects, queryAnchor, error in
    }
    
    let query = HKAnchoredObjectQuery(type: HKObjectType.quantityType(forIdentifier: quantityTypeIdentifier)!,
                                      predicate: queryPredicate,
                                      anchor: nil,
                                      limit: HKObjectQueryNoLimit,
                                      resultsHandler: updateHandler)
        guard let samples = samples as? [HKQuantitySample] else { return }
        for sample in samples {
            if quantityTypeIdentifier == .heartRate {
                let heartRate = sample.quantity.doubleValue(for: HKUnit(from: "count/min"))
                self.heartRateData.append(heartRate)
            }
          
            query.updateHandler = updateHandler
        }
    healthStore.execute(query)
    activeDataQueries.append(query)
  }
  
  func fetchRespiratoryRate() {
    guard let respiratoryType = HKObjectType.quantityType(forIdentifier: .respiratoryRate) else { return }
    let query = HKSampleQuery(sampleType: respiratoryType, predicate: nil, limit: 1, sortDescriptors: nil) { query, samples, error in
        guard let sample = samples?.first as? HKQuantitySample else { return }
        let rate = sample.quantity.doubleValue(for: HKUnit(from: "count/min"))
        self.respiratoryRateData.append(rate)
    }
    healthStore.execute(query)
}

func calculateHRV() {
    guard heartRateData.count >= 2 else { return }
    let intervals = heartRateData.windows(ofCount: 2).map { 60.0 / $0.first! - 60.0 / $0.last! }
    let hrv = intervals.reduce(0, +) / Double(intervals.count) * 1000  // Simplified HRV in ms
    self.hrvData.append(hrv)
}

func fetchLastSleepTime() {
    guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }
    let query = HKSampleQuery(sampleType: sleepType, predicate: nil, limit: 1, sortDescriptors: nil) { query, samples, error in
        guard let sample = samples?.first as? HKCategorySample else { return }
        let lastSleepEnd = sample.endDate
        self.circadianTime = Date().timeIntervalSince(lastSleepEnd)
    }
    healthStore.execute(query)
}

func detectREM() -> Bool {
    guard !accelerometerOutput.isEmpty, !heartRateData.isEmpty, !hrvData.isEmpty else { return false }
    let recentMovement = (accelerometerOutput.suffix(10) as NSArray).value(forKeyPath: "@avg.self") as? Double ?? 0.0
    let recentHeartRate = heartRateData.suffix(10).reduce(0, +) / 10
    let recentHRV = hrvData.suffix(10).reduce(0, +) / 10
    // Placeholder: Low movement, elevated heart rate, high HRV
    return recentMovement < 0.1 && recentHeartRate > 60 && recentHRV > 30
}

func checkForREM() {
    if detectREM() {
        WKInterfaceDevice.current().play(.notification)  // Vibrate for lucid dreaming
        print("REM detected - alert triggered")
    }
}
  
  func stopAccumulatingData() {
     motionManager.stopAccelerometerUpdates()
    for query in activeDataQueries {
      healthStore.stop(query)
    }
    
    activeDataQueries.removeAll()
    stopTimer()
    remTimer?.invalidate()
  }
  
  func pauseAccumulatingData() {
    DispatchQueue.main.sync {
      isPaused = true
    }
  }
  
  func resumeAccumulatingData() {
    DispatchQueue.main.sync {
      isPaused = false
    }
  }
  
  func stopTimer() {
    timer?.invalidate()
  }
  
  func startMotionCapture(){
    
    print("Motion capture starting...");
    motionManager.accelerometerUpdateInterval = 1.0/60.0;
    print("Set accelerometer update interval...");
    
    if (motionManager.isAccelerometerAvailable) {
      
      print("Creating handler...");
      let handler:CMAccelerometerHandler = {(data: CMAccelerometerData?, error: Error?) -> Void in
        
        if(data != nil){
          let output : [Double] = [ Date().timeIntervalSince1970, data!.acceleration.x, data!.acceleration.y, data!.acceleration.z]
          
          // Mutated
          self.accelerometerOutput.add(output)
          self.counter = self.counter + 1;
          
          // Size checked
          if(self.threshold <= self.counter){
            
            print("Time to post...");
            self.counter = 0;
            self.accelerometerOutputPost = self.accelerometerOutput.mutableCopy() as! NSMutableArray
            self.accelerometerOutput = NSMutableArray()
            
            self.pushToPhone()
          }
        }
      }
      
      print("Sending accelerometer updates to queue...");
      motionManager.startAccelerometerUpdates(to: OperationQueue.main, withHandler: handler)
      
    }
    else {
      print("No accelerometer available.")
    }
  }
  
  func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
    print("Workout session did fail with error: \(error)")
  }
  
  func workoutSession(_ workoutSession: HKWorkoutSession, didGenerate event: HKWorkoutEvent) {
    workoutEvents.append(event)
  }
  
  func workoutSession(_ workoutSession: HKWorkoutSession,
                      didChangeTo toState: HKWorkoutSessionState,
                      from fromState: HKWorkoutSessionState,
                      date: Date) {
    switch toState {
    case .running:
      if fromState == .notStarted {
        startAccumulatingData(startDate: workoutStartDate!)
      } else {
        resumeAccumulatingData()
      }
      
    case .paused:
      pauseAccumulatingData()
      
    case .ended:
      stopAccumulatingData()
      saveWorkout()
    default:
      break
    }
  }
  
  private func saveWorkout() {
    
    let configuration = workoutSession!.workoutConfiguration
    
    let workout = HKWorkout(activityType: configuration.activityType, start: workoutStartDate!, end: workoutEndDate!)
    
    WKInterfaceController.reloadRootControllers(withNamesAndContexts: [(name: "CompletionInterfaceController", context: [workout] as AnyObject)])

  }
}

extension SleepInterfaceController: WCSessionDelegate {
  func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
    print("Session activation for HR completed")
  }
  func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
    print("Received application context: ", applicationContext)
  }
}

