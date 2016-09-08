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
                    self.startButton.setTitleColor(UIColor(red: 83.0 / 255.0, green: 215.0 / 255.0, blue: 105.0 / 255.0, alpha: 1), for: UIControlState.normal)
                    self.startButton.setBackgroundImage(UIImage(named: "green"), for: UIControlState.normal)
                case .stopped:
                    self.resetButton.setTitle("Reset", for: UIControlState.normal)
                    self.startButton.setTitle("Start", for: UIControlState.normal)
                    self.startButton.setTitleColor(UIColor(red: 83.0 / 255.0, green: 215.0 / 255.0, blue: 105.0 / 255.0, alpha: 1), for: UIControlState.normal)
                    self.startButton.setBackgroundImage(UIImage(named: "green"), for: UIControlState.normal) // 重复代码
                case .timing:
                    self.resetButton.setTitle("Lap", for: UIControlState.normal)
                    self.resetButton.isEnabled = true
                    self.startButton.setTitle("Stop", for: UIControlState.normal)
                    self.startButton.setTitleColor(UIColor(red: 252.0 / 255.0, green: 61.0 / 255.0, blue: 57.0 / 255.0, alpha: 1), for: UIControlState.normal)
                    self.startButton.setBackgroundImage(UIImage(named: "red"), for: UIControlState.normal)
                }
            })
            .addDisposableTo(disposeBag)

        let timeInfo = automaton.state.asObservable()
            .flatMapLatest { state -> Observable<State> in
                switch state {
                case .reseted:
                    return Observable.just(State.reseted)
                case .stopped:
                    return Observable.just(State.stopped)
                case .timing:
                    return Observable<Int>.interval(0.001, scheduler: MainScheduler.instance).map { _ in State.timing }
                }
            }
            .scan(0) { (acc: TimeInterval, x: State) in
                switch x {
                case .reseted: return 0
                case .stopped: return acc
                case .timing: return acc + 0.01
                }
            }
            .shareReplay(1)

        timeInfo
            .map(convertToTimeInfo).map(Optional.init)
            .bindTo(displayTimeLabel.rx.text)
            .addDisposableTo(disposeBag)

        timeInfo
            .sample(resetButton.rx.tap)
            .withLatestFrom(automaton.state.asObservable()) { (sample: $0, state: $1) }
            .scan((preTime: 0, info: [(lap: String, time: TimeInterval)]())) { (acc, x) -> (preTime: TimeInterval, info: [(lap: String, time: TimeInterval)]) in
                switch x.state {
                case .reseted:
                    return (preTime: 0, info: [])
                case .stopped, .timing:
                    return (preTime: x.sample, info: [(lap: "Lap \(acc.info.count + 1)", time: x.sample - acc.preTime)] + acc.info)
                }
            }
            .map { $0.info.map { (lap: $0, time: convertToTimeInfo($1)) } }
            .bindTo(lapsTableView.rx.items(cellIdentifier: "LapTableViewCell")) { index, element, cell in
                cell.textLabel?.text = element.lap
                cell.detailTextLabel?.text = element.time // convertToTimeInfo(element.time)
            }
            .addDisposableTo(disposeBag)

    }

}
