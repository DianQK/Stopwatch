//
//  ViewController.swift
//  Stopwatch
//
//  Created by DianQK on 9/8/16.
//  Copyright © 2016 T. All rights reserved.
//

import UIKit
import RxSwift
import RxCocoa
import RxAutomaton

let convertToTimeInfo: (TimeInterval) -> String = { ms in
    var form = DateFormatter()
    form.dateFormat = "mm:ss.SS"
    let date = Date(timeIntervalSince1970: ms)
    return form.string(from: date)
}

struct Color {
    static let red = UIColor(red: 252.0 / 255.0, green: 61.0 / 255.0, blue: 57.0 / 255.0, alpha: 1)
    static let green = UIColor(red: 83.0 / 255.0, green: 215.0 / 255.0, blue: 105.0 / 255.0, alpha: 1)
}

class ViewController: UIViewController {

    @IBOutlet private weak var displayTimeLabel: UILabel!
    @IBOutlet private weak var resetButton: UIButton!
    @IBOutlet private weak var startButton: UIButton!
    @IBOutlet private weak var lapsTableView: UITableView!

    private let disposeBag = DisposeBag()

    private enum Input {
        case start, stop, lap, reset
    }

    private enum State {
        case timing, stopped, reseted
    }

    private var automaton: Automaton<State, Input>!

    override func viewDidLoad() {
        super.viewDidLoad()

        let mappings: [Automaton<State, Input>.NextMapping] = [
        /*  Input  | fromState => toState                        |  Effect */
        /* ----------------------------------------------------------------*/
            .start | ([.reseted, .stopped].contains => .timing)  | .empty(),
            .stop  | (.timing                       => .stopped) | .empty(),
            .reset | (.stopped                      => .reseted) | .empty(),
        ]

        let(inputSignal, inputObserver) = Observable<Input>.pipe()

        let automaton: Automaton<State, Input> = Automaton(state: .reseted, input: inputSignal, mapping: reduce(mappings), strategy: .latest)
        self.automaton = automaton
        
        Observable.from([
            startButton.rx.tap
                .withLatestFrom(automaton.state.asObservable())
                .map { state -> Input in
                    switch state {
                    case .reseted, .stopped: return .start
                    case .timing: return .stop
                    }
                },
            resetButton.rx.tap
                .withLatestFrom(automaton.state.asObservable())
                .flatMap { (state) -> Observable<Input> in
                    switch state {
                    case .reseted, .timing: return Observable.empty()
                    case .stopped: return Observable.just(.reset)
                    }
                },
            ])
            .merge()
            .subscribe(onNext: inputObserver.onNext)
            .addDisposableTo(disposeBag)

        automaton.state.asObservable()
            .subscribe(onNext: { [weak self] state in
                guard let `self` = self else { return }
                switch state {
                case .reseted:
                    self.resetButton.setTitle("Lap", for: UIControlState.normal)
                    self.resetButton.isEnabled = false
                    self.displayTimeLabel.text = convertToTimeInfo(0)
                    self.startButton.setTitle("Start", for: UIControlState.normal)
                    self.startButton.setTitleColor(Color.green, for: UIControlState.normal)
                    self.startButton.setBackgroundImage(UIImage(named: "green"), for: UIControlState.normal)
                case .stopped:
                    self.resetButton.setTitle("Reset", for: UIControlState.normal)
                    self.startButton.setTitle("Start", for: UIControlState.normal)
                    self.startButton.setTitleColor(Color.green, for: UIControlState.normal)
                    self.startButton.setBackgroundImage(UIImage(named: "green"), for: UIControlState.normal) // 重复代码
                case .timing:
                    self.resetButton.setTitle("Lap", for: UIControlState.normal)
                    self.resetButton.isEnabled = true
                    self.startButton.setTitle("Stop", for: UIControlState.normal)
                    self.startButton.setTitleColor(Color.red, for: UIControlState.normal)
                    self.startButton.setBackgroundImage(UIImage(named: "red"), for: UIControlState.normal)
                }
            })
            .addDisposableTo(disposeBag)

        let timeInfo = automaton.state.asObservable()
            .flatMapLatest { state -> Observable<State> in
                switch state {
                case .reseted, .stopped:
                    return Observable.just(state)
                case .timing:
                    return Observable<Int>.interval(0.01, scheduler: MainScheduler.instance).map { _ in State.timing }
                }
            }
            .scan((time: 0, state: State.reseted)) { (acc, x) -> (time: TimeInterval, state: State) in
                switch x {
                case .reseted: return (time: 0, state: x)
                case .stopped: return (time: acc.time, state: x)
                case .timing: return (time: acc.time + 0.01, state: x)
                }
            }
            .shareReplay(1)

        timeInfo
            .map { $0.time }
            .map(convertToTimeInfo).map(Optional.init)
            .bindTo(displayTimeLabel.rx.text)
            .addDisposableTo(disposeBag)

        let lap = Observable.from([
            resetButton.rx.tap.asObservable(),
            automaton.state.asObservable()
                .scan((pre: State.reseted, current: State.reseted)) { acc, x in
                    (pre: acc.current, current: x)
                }
                .flatMap { state -> Observable<Void> in
                    if state.pre == .reseted && state.current == .timing {
                        return Observable.just(())
                    } else {
                        return Observable.empty()
                    }
                }
                .delay(0.001, scheduler: MainScheduler.instance)
            ])
        .merge()

        timeInfo
            .sample(lap)
            .scan((preTime: 0, max: 0, min: 0, info: [(lap: String, time: Observable<TimeInterval>)]())) { (acc, x) -> (preTime: TimeInterval, max: TimeInterval, min: TimeInterval, info: [(lap: String, time: Observable<TimeInterval>)]) in
                switch x.state {
                case .reseted:
                    return (preTime: 0, max: 0, min: 0, info: [])
                case .timing, .stopped:
                    let offset = x.time - acc.preTime
                    if let _ = acc.info.first {
                        let info = [(lap: "Lap \(acc.info.count + 1)", time: timeInfo.map { $0.time - x.time }), (lap: "Lap \(acc.info.count)", time: Observable<TimeInterval>.just(offset))]
                            + acc.info.dropFirst()
                        return (preTime: x.time, max: offset >= acc.max ? offset : acc.max, min: offset <= acc.min ?offset : acc.min, info: info)
                    } else {
                        return (preTime: 0, max: 0, min: Double.infinity, info: [(lap: "Lap 1", time: timeInfo.map { $0.time })])
                    }
                }
            }
            .map { (info) in
                info.info.map { (lap: $0.lap, max: info.max, min: info.min, time: $0.time) }
            }
            .bindTo(lapsTableView.rx.items(cellIdentifier: "LapTableViewCell")) { index, element, cell in
                if let timeLabel = cell.detailTextLabel {
                    element.time.map(convertToTimeInfo).map(Optional.init).bindTo(timeLabel.rx.text).addDisposableTo(cell.rx.prepareForReuseBag)
                    element.time
                        .take(1)
                        .map { (time) -> UIColor in
                            guard element.max != element.min && time != 0 else {
                                return UIColor.white
                            }
                            if time == element.max {
                                return Color.red
                            } else if time == element.min {
                                return Color.green
                            } else {
                                return UIColor.white
                            }
                        }
                        .subscribe(onNext: {
                            timeLabel.textColor = $0
                        })
                        .addDisposableTo(cell.rx.prepareForReuseBag)
                }
                cell.textLabel?.text = element.lap
            }
            .addDisposableTo(disposeBag)
    }
}
