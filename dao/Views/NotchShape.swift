import SwiftUI

// 路径实现基于 DynamicNotchKit（https://github.com/MrKai77/DynamicNotchKit）
// Copyright (c) 2025 Kai Azim — MIT License
// （boring.notch 同款 6pt/14pt 圆角参数，本项目独立整理实现）
// MIT License 全文：https://github.com/MrKai77/DynamicNotchKit/blob/main/LICENSE

/// 灵动岛外形（参照 boring.notch 的设计）
///
/// - 顶部左右：小圆角（6pt）——与屏幕边缘自然连接
/// - 底部左右：大圆角（14pt）
/// - 四角均为标准凸弧圆角（quadCurve，control 在边缘上，弧线圆润）
struct NotchShape: Shape {
    /// 顶部圆角半径（小圆角）
    var topCornerRadius: CGFloat = 6
    /// 底部圆角半径（大圆角）
    var bottomCornerRadius: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // 左上角顶点
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // 左上圆角（小圆角）
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY + topCornerRadius),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY)
        )

        // 左边缘
        path.addLine(to: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY - bottomCornerRadius))

        // 左下圆角（大圆角）
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius + bottomCornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY)
        )

        // 底部直线
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius - bottomCornerRadius, y: rect.maxY))

        // 右下圆角（大圆角）
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY - bottomCornerRadius),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY)
        )

        // 右边缘
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY + topCornerRadius))

        // 右上圆角（小圆角）
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY)
        )

        path.closeSubpath()
        return path
    }
}
