//
//  TableViewDragger.swift
//  TableViewDragger
//
//  Created by Kyohei Ito on 2015/09/24.
//  Copyright © 2015年 kyohei_ito. All rights reserved.
//

import UIKit

@objc public protocol TableViewDraggerDelegate: class {
    /// If allow movement of cell, please return `true`. require a call to `moveRowAt:toIndexPath:` of UITableView and rearranged of data.
    func dragger(_ dragger: TableViewDragger, moveDraggingAt indexPath: IndexPath, newIndexPath: IndexPath) -> Bool

    /// If allow dragging of cell, prease return `true`.
    @objc optional func dragger(_ dragger: TableViewDragger, shouldDragAt indexPath: IndexPath) -> Bool
    @objc optional func dragger(_ dragger: TableViewDragger, willBeginDraggingAt indexPath: IndexPath)
    @objc optional func dragger(_ dragger: TableViewDragger, didBeginDraggingAt indexPath: IndexPath)
    @objc optional func dragger(_ dragger: TableViewDragger, willEndDraggingAt indexPath: IndexPath)
    @objc optional func dragger(_ dragger: TableViewDragger, didEndDraggingAt indexPath: IndexPath)
}

@objc public protocol TableViewDraggerDataSource: class {
    /// Return any cell if want to change the cell in drag.
    @objc optional func dragger(_ dragger: TableViewDragger, cellForRowAt indexPath: IndexPath) -> UITableViewCell?
    /// Return the indexPath if want to change the indexPath to start drag.
    @objc optional func dragger(_ dragger: TableViewDragger, indexPathForDragAt indexPath: IndexPath) -> IndexPath
}

open class TableViewDragger: NSObject {
    let longPressGesture = UILongPressGestureRecognizer()
    let panGesture = UIPanGestureRecognizer()
    var draggingCell: TableViewDraggerCell?
    var displayLink: CADisplayLink?
    var targetClipsToBounds = true
    weak var targetTableView: UITableView?
    private var draggingDirection: UIScrollView.DraggingDirection?

    /// It will be `true` if want to hide the original cell.
    open var isHiddenOriginCell: Bool = true
    /// Zoom scale of cell in drag.
    open var zoomScaleForCell: CGFloat = 1
    /// Alpha of cell in drag.
    open var alphaForCell: CGFloat = 1
    /// Opacity of cell shadow in drag.
    open var opacityForShadowOfCell: Float = 0.4
    /// Velocity of auto scroll in drag.
    open var scrollVelocity: CGFloat = 1
    open weak var delegate: TableViewDraggerDelegate?
    open weak var dataSource: TableViewDraggerDataSource?
    open var tableView: UITableView? {
        return targetTableView
    }

    /// `UITableView` want to drag.
    public init(tableView: UITableView) {
        super.init()

        self.targetTableView = tableView
        tableView.addGestureRecognizer(longPressGesture)
        tableView.addGestureRecognizer(panGesture)

        longPressGesture.addTarget(self, action: #selector(TableViewDragger.longPressGestureAction(_:)))
        longPressGesture.delegate = self
        longPressGesture.allowableMovement = 5.0

        panGesture.addTarget(self, action: #selector(TableViewDragger.panGestureAction(_:)))
        panGesture.delegate = self
        panGesture.maximumNumberOfTouches = 1
    }

    deinit {
        targetTableView?.removeGestureRecognizer(longPressGesture)
        targetTableView?.removeGestureRecognizer(panGesture)
    }

    func targetIndexPath(_ tableView: UITableView, draggingCell: TableViewDraggerCell) -> IndexPath {
        let location        = draggingCell.location
        let offsetY         = (draggingCell.viewHeight / 2) + 2
        let offsetX         = tableView.center.x
        let topPoint        = CGPoint(x: offsetX, y: location.y - offsetY)
        let bottomPoint     = CGPoint(x: offsetX, y: location.y + offsetY)
        let point           = draggingDirection == .up ? topPoint : bottomPoint

        if let targetIndexPath = tableView.indexPathForRow(at: point) {
            if tableView.cellForRow(at: targetIndexPath) == nil {
                return draggingCell.dropIndexPath
            }

            let targetRect = tableView.rectForRow(at: targetIndexPath)
            let targetCenterY = targetRect.origin.y + (targetRect.height / 2)

            guard let direction = draggingDirection else {
                return draggingCell.dropIndexPath
            }

            switch direction {
            case .up:
                if (targetCenterY > point.y && draggingCell.dropIndexPath > targetIndexPath) {
                    return targetIndexPath
                }
            case .down:
                if (targetCenterY < point.y && draggingCell.dropIndexPath < targetIndexPath) {
                    return targetIndexPath
                }
            }
        }

        return draggingCell.dropIndexPath
    }

    func dragCell(_ tableView: UITableView, draggingCell: TableViewDraggerCell) {
        let indexPath = targetIndexPath(tableView, draggingCell: draggingCell)
        if draggingCell.dropIndexPath.compare(indexPath) == .orderedSame {
            return
        }

        if let cell = tableView.cellForRow(at: draggingCell.dropIndexPath) {
            cell.isHidden = isHiddenOriginCell
        }
        if delegate?.dragger(self, moveDraggingAt: draggingCell.dropIndexPath, newIndexPath: indexPath) == true {
            draggingCell.dropIndexPath = indexPath
        }
    }

    func copiedCell(at indexPath: IndexPath, retryCount: Int) -> UITableViewCell? {
        var cell = dataSource?.dragger?(self, cellForRowAt: indexPath)
        if cell == nil, let tableView = targetTableView {
            cell = tableView.dataSource?.tableView(tableView, cellForRowAt: indexPath)
        }

        if cell?.isHidden == true {
            if retryCount > 10 {
                return nil
            }
            // retry
            return copiedCell(at: indexPath, retryCount: retryCount + 1)
        }

        return cell
    }

    func draggedCell(_ tableView: UITableView, indexPath: IndexPath) -> TableViewDraggerCell? {
        guard let copiedCell = copiedCell(at: indexPath, retryCount: 0) else {
            return nil
        }

        let cellRect = tableView.rectForRow(at: indexPath)
        copiedCell.bounds.size = cellRect.size

        if let height = tableView.delegate?.tableView?(tableView, heightForRowAt: indexPath) {
            copiedCell.bounds.size.height = height
        }

        let cell = TableViewDraggerCell(cell: copiedCell)
        cell.dragScale = zoomScaleForCell
        cell.dragAlpha = alphaForCell
        cell.dragShadowOpacity = opacityForShadowOfCell
        cell.dropIndexPath = indexPath

        return cell
    }
}

// MARK: - Dragging Cell
extension TableViewDragger {
    private func draggingDidBegin(_ gesture: UIGestureRecognizer, indexPath: IndexPath) {
        displayLink?.invalidate()
        displayLink = UIScreen.main.displayLink(withTarget: self, selector: #selector(TableViewDragger.displayDidRefresh(_:)))
        displayLink?.add(to: .main, forMode: .defaultRunLoopMode)
        displayLink?.isPaused = true

        let dragIndexPath = dataSource?.dragger?(self, indexPathForDragAt: indexPath) ?? indexPath
        delegate?.dragger?(self, willBeginDraggingAt: dragIndexPath)

        if let tableView = targetTableView {
            let actualCell = tableView.cellForRow(at: dragIndexPath)
            actualCell?.isHidden = isHiddenOriginCell

            if let draggedCell = draggedCell(tableView, indexPath: dragIndexPath) {
                let point = gesture.location(in: actualCell)
                draggedCell.offset = point
                draggedCell.transformToPoint(point)
                draggedCell.location = gesture.location(in: tableView)
                tableView.addSubview(draggedCell)

                draggingCell = draggedCell
            }

            targetClipsToBounds = tableView.clipsToBounds
            tableView.clipsToBounds = false
        }

        delegate?.dragger?(self, didBeginDraggingAt: indexPath)
    }

    private func draggingDidChange(_ gesture: UIGestureRecognizer, direction: UIScrollView.DraggingDirection?) {
        guard let tableView = targetTableView, let draggingCell = draggingCell else {
            return
        }

        draggingCell.location = gesture.location(in: tableView)

        if let adjustedDirection = tableView.draggingDirection(at: draggingCell.adjustedCenter(on: tableView)) {
            displayLink?.isPaused = false
            draggingDirection = adjustedDirection
        } else {
            draggingDirection = direction
        }

        dragCell(tableView, draggingCell: draggingCell)
    }

    private func draggingDidEnd(_ gesture: UIGestureRecognizer) {
        displayLink?.invalidate()
        displayLink = nil

        guard let tableView = targetTableView, let draggingCell = draggingCell else {
            return
        }

        delegate?.dragger?(self, willEndDraggingAt: draggingCell.dropIndexPath)

        let targetRect = tableView.rectForRow(at: draggingCell.dropIndexPath)
        let center = CGPoint(x: targetRect.width / 2, y: targetRect.origin.y + (targetRect.height / 2))

        draggingCell.drop(center) {
            self.delegate?.dragger?(self, didEndDraggingAt: draggingCell.dropIndexPath)

            if let cell = tableView.cellForRow(at: draggingCell.dropIndexPath) {
                cell.isHidden = false
            }

            tableView.clipsToBounds = self.targetClipsToBounds

            self.draggingCell = nil
        }
    }
}

// MARK: - Action Methods
private extension TableViewDragger {
    @objc func displayDidRefresh(_ displayLink: CADisplayLink) {
        guard let tableView = targetTableView, let draggingCell = draggingCell else {
            return
        }

        let center = draggingCell.adjustedCenter(on: tableView)

        if let direction = tableView.draggingDirection(at: center) {
            draggingDirection = direction
        } else {
            displayLink.isPaused = true
        }

        tableView.contentOffset = tableView.preferredContentOffset(at: center, velocity: scrollVelocity)

        dragCell(tableView, draggingCell: draggingCell)

        draggingCell.location = panGesture.location(in: tableView)
    }

    @objc func longPressGestureAction(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            targetTableView?.isScrollEnabled = false

            let point = gesture.location(in: targetTableView)
            if let path = targetTableView?.indexPathForRow(at: point) {
                draggingDidBegin(gesture, indexPath: path)
            }
        case .ended, .cancelled:
            draggingDidEnd(gesture)

            targetTableView?.isScrollEnabled = true

        case .changed, .failed, .possible:
            break
        }
    }

    @objc func panGestureAction(_ gesture: UIPanGestureRecognizer) {
        guard targetTableView?.isScrollEnabled == false && gesture.state == .changed else {
            return
        }

        let offsetY = gesture.translation(in: targetTableView).y
        if offsetY < 0 {
            draggingDidChange(gesture, direction: .up)
        } else if offsetY > 0 {
            draggingDidChange(gesture, direction: .down)
        } else {
            draggingDidChange(gesture, direction: nil)
        }

        gesture.setTranslation(.zero, in: targetTableView)
    }
}

// MARK: - UIGestureRecognizerDelegate Methods
extension TableViewDragger: UIGestureRecognizerDelegate {
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer == longPressGesture {
            let point = touch.location(in: targetTableView)

            if let indexPath = targetTableView?.indexPathForRow(at: point) {
                if let ret = delegate?.dragger?(self, shouldDragAt: indexPath) {
                    return ret
                }
            } else {
                return false
            }
        }

        return true
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return gestureRecognizer == panGesture || otherGestureRecognizer == panGesture || gestureRecognizer == longPressGesture || otherGestureRecognizer == longPressGesture
    }
}
