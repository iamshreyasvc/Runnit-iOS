//
//  CountryOutline.swift
//  Runnit iOS
//
//  Simple stroked country silhouettes, used as railway icons in the add-trip flow
//  (India for Indian Railways, the US for Amtrak). SF Symbols has no country
//  shapes, so these are lightweight hand-simplified outlines: each is a closed
//  polyline in a unit square, aspect-corrected for latitude and centred, so it
//  draws faithfully at any icon size.
//
//  Point data is derived from public country geometry (Natural Earth via
//  johan/world.geo.json), simplified to a few dozen vertices — enough to read as
//  the country at a glance, small enough to keep inline.
//

import SwiftUI

/// A closed country outline that scales to fit any rect, preserving its aspect
/// (the points are already normalised into a centred unit square).
struct CountryOutline: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }
        let side = min(rect.width, rect.height)
        let originX = rect.minX + (rect.width - side) / 2
        let originY = rect.minY + (rect.height - side) / 2
        func map(_ p: CGPoint) -> CGPoint {
            CGPoint(x: originX + p.x * side, y: originY + p.y * side)
        }
        path.move(to: map(points[0]))
        for p in points.dropFirst() { path.addLine(to: map(p)) }
        path.closeSubpath()
        return path
    }

    static var india: CountryOutline { CountryOutline(points: CountryOutlineData.india) }
    static var unitedStates: CountryOutline { CountryOutline(points: CountryOutlineData.unitedStates) }
}

private enum CountryOutlineData {
    // india: 100 points
    static let india: [CGPoint] = [
        CGPoint(x: 0.3362, y: 0.0), CGPoint(x: 0.3718, y: 0.0426),
        CGPoint(x: 0.3684, y: 0.0722), CGPoint(x: 0.3816, y: 0.0908),
        CGPoint(x: 0.3805, y: 0.1093), CGPoint(x: 0.3568, y: 0.1045),
        CGPoint(x: 0.366, y: 0.1445), CGPoint(x: 0.4445, y: 0.1929),
        CGPoint(x: 0.4235, y: 0.2094), CGPoint(x: 0.4107, y: 0.2434),
        CGPoint(x: 0.517, y: 0.2953), CGPoint(x: 0.5623, y: 0.3),
        CGPoint(x: 0.5814, y: 0.3185), CGPoint(x: 0.6743, y: 0.3298),
        CGPoint(x: 0.6763, y: 0.2767), CGPoint(x: 0.6965, y: 0.2691),
        CGPoint(x: 0.6999, y: 0.305), CGPoint(x: 0.73, y: 0.3187),
        CGPoint(x: 0.8057, y: 0.3144), CGPoint(x: 0.808, y: 0.2921),
        CGPoint(x: 0.7945, y: 0.2805), CGPoint(x: 0.8212, y: 0.276),
        CGPoint(x: 0.8894, y: 0.2258), CGPoint(x: 0.9172, y: 0.2347),
        CGPoint(x: 0.9407, y: 0.2195), CGPoint(x: 0.9563, y: 0.242),
        CGPoint(x: 0.9451, y: 0.2573), CGPoint(x: 0.9807, y: 0.2627),
        CGPoint(x: 0.9832, y: 0.2765), CGPoint(x: 0.9716, y: 0.2832),
        CGPoint(x: 0.9744, y: 0.3055), CGPoint(x: 0.9507, y: 0.2989),
        CGPoint(x: 0.9079, y: 0.324), CGPoint(x: 0.9089, y: 0.3448),
        CGPoint(x: 0.8742, y: 0.423), CGPoint(x: 0.8484, y: 0.4147),
        CGPoint(x: 0.8431, y: 0.4801), CGPoint(x: 0.8268, y: 0.4887),
        CGPoint(x: 0.8094, y: 0.4311), CGPoint(x: 0.8003, y: 0.4312),
        CGPoint(x: 0.7949, y: 0.4544), CGPoint(x: 0.7768, y: 0.4356),
        CGPoint(x: 0.787, y: 0.4149), CGPoint(x: 0.8018, y: 0.4128),
        CGPoint(x: 0.817, y: 0.3821), CGPoint(x: 0.7358, y: 0.3714),
        CGPoint(x: 0.7329, y: 0.3461), CGPoint(x: 0.6909, y: 0.3287),
        CGPoint(x: 0.6792, y: 0.3533), CGPoint(x: 0.7031, y: 0.3725),
        CGPoint(x: 0.6751, y: 0.3993), CGPoint(x: 0.6954, y: 0.409),
        CGPoint(x: 0.6898, y: 0.4309), CGPoint(x: 0.7064, y: 0.4882),
        CGPoint(x: 0.7017, y: 0.5014), CGPoint(x: 0.6384, y: 0.5085),
        CGPoint(x: 0.6403, y: 0.5358), CGPoint(x: 0.6227, y: 0.5573),
        CGPoint(x: 0.5751, y: 0.5818), CGPoint(x: 0.4803, y: 0.6712),
        CGPoint(x: 0.4802, y: 0.6879), CGPoint(x: 0.4185, y: 0.7118),
        CGPoint(x: 0.4086, y: 0.7395), CGPoint(x: 0.4172, y: 0.8169),
        CGPoint(x: 0.4032, y: 0.8514), CGPoint(x: 0.4031, y: 0.9131),
        CGPoint(x: 0.3859, y: 0.9149), CGPoint(x: 0.3709, y: 0.9426),
        CGPoint(x: 0.381, y: 0.9546), CGPoint(x: 0.3508, y: 0.9649),
        CGPoint(x: 0.3264, y: 1.0), CGPoint(x: 0.2951, y: 0.9661),
        CGPoint(x: 0.2671, y: 0.8786), CGPoint(x: 0.2379, y: 0.8265),
        CGPoint(x: 0.224, y: 0.7584), CGPoint(x: 0.1939, y: 0.7085),
        CGPoint(x: 0.164, y: 0.5136), CGPoint(x: 0.1159, y: 0.5353),
        CGPoint(x: 0.0926, y: 0.531), CGPoint(x: 0.0494, y: 0.4869),
        CGPoint(x: 0.0653, y: 0.4738), CGPoint(x: 0.0556, y: 0.4596),
        CGPoint(x: 0.0168, y: 0.4287), CGPoint(x: 0.0388, y: 0.4045),
        CGPoint(x: 0.1116, y: 0.4046), CGPoint(x: 0.105, y: 0.3734),
        CGPoint(x: 0.0864, y: 0.355), CGPoint(x: 0.0826, y: 0.327),
        CGPoint(x: 0.061, y: 0.3107), CGPoint(x: 0.0974, y: 0.2726),
        CGPoint(x: 0.1358, y: 0.2754), CGPoint(x: 0.2233, y: 0.164),
        CGPoint(x: 0.2228, y: 0.1381), CGPoint(x: 0.251, y: 0.1171),
        CGPoint(x: 0.2243, y: 0.0991), CGPoint(x: 0.2011, y: 0.0427),
        CGPoint(x: 0.2173, y: 0.0271), CGPoint(x: 0.2674, y: 0.0359),
        CGPoint(x: 0.3043, y: 0.0305), CGPoint(x: 0.3362, y: 0.0),
    ]

    // unitedStates (contiguous): 121 points
    static let unitedStates: [CGPoint] = [
        CGPoint(x: 0.5175, y: 0.2332), CGPoint(x: 0.5259, y: 0.2489),
        CGPoint(x: 0.5725, y: 0.2606), CGPoint(x: 0.6135, y: 0.2632),
        CGPoint(x: 0.629, y: 0.257), CGPoint(x: 0.6897, y: 0.2878),
        CGPoint(x: 0.6944, y: 0.2979), CGPoint(x: 0.7024, y: 0.2963),
        CGPoint(x: 0.7141, y: 0.3077), CGPoint(x: 0.7119, y: 0.3116),
        CGPoint(x: 0.73, y: 0.3219), CGPoint(x: 0.7371, y: 0.3609),
        CGPoint(x: 0.7201, y: 0.3936), CGPoint(x: 0.7276, y: 0.4025),
        CGPoint(x: 0.7925, y: 0.3764), CGPoint(x: 0.7885, y: 0.3632),
        CGPoint(x: 0.7963, y: 0.3597), CGPoint(x: 0.8293, y: 0.3596),
        CGPoint(x: 0.8631, y: 0.3295), CGPoint(x: 0.9213, y: 0.3293),
        CGPoint(x: 0.936, y: 0.3194), CGPoint(x: 0.9474, y: 0.2924),
        CGPoint(x: 0.9606, y: 0.2758), CGPoint(x: 0.9857, y: 0.2842),
        CGPoint(x: 0.9857, y: 0.3141), CGPoint(x: 1.0, y: 0.3337),
        CGPoint(x: 0.9454, y: 0.3584), CGPoint(x: 0.9333, y: 0.3764),
        CGPoint(x: 0.9331, y: 0.388), CGPoint(x: 0.9388, y: 0.3997),
        CGPoint(x: 0.946, y: 0.4002), CGPoint(x: 0.9442, y: 0.3922),
        CGPoint(x: 0.9494, y: 0.3971), CGPoint(x: 0.948, y: 0.4033),
        CGPoint(x: 0.8831, y: 0.4188), CGPoint(x: 0.9086, y: 0.4147),
        CGPoint(x: 0.9137, y: 0.4189), CGPoint(x: 0.8789, y: 0.4228),
        CGPoint(x: 0.8737, y: 0.4289), CGPoint(x: 0.8788, y: 0.4299),
        CGPoint(x: 0.875, y: 0.4457), CGPoint(x: 0.8624, y: 0.4626),
        CGPoint(x: 0.8516, y: 0.4503), CGPoint(x: 0.8598, y: 0.4743),
        CGPoint(x: 0.8445, y: 0.5004), CGPoint(x: 0.8483, y: 0.4846),
        CGPoint(x: 0.8394, y: 0.4762), CGPoint(x: 0.8374, y: 0.4579),
        CGPoint(x: 0.8341, y: 0.4674), CGPoint(x: 0.8378, y: 0.4814),
        CGPoint(x: 0.8263, y: 0.4779), CGPoint(x: 0.8382, y: 0.485),
        CGPoint(x: 0.839, y: 0.5059), CGPoint(x: 0.844, y: 0.5074),
        CGPoint(x: 0.8482, y: 0.537), CGPoint(x: 0.8372, y: 0.5533),
        CGPoint(x: 0.8193, y: 0.5598), CGPoint(x: 0.7904, y: 0.5821),
        CGPoint(x: 0.751, y: 0.6272), CGPoint(x: 0.7514, y: 0.658),
        CGPoint(x: 0.7732, y: 0.7273), CGPoint(x: 0.7719, y: 0.7507),
        CGPoint(x: 0.7624, y: 0.7668), CGPoint(x: 0.7539, y: 0.7642),
        CGPoint(x: 0.7273, y: 0.7138), CGPoint(x: 0.7283, y: 0.6907),
        CGPoint(x: 0.7234, y: 0.6786), CGPoint(x: 0.7031, y: 0.6568),
        CGPoint(x: 0.6857, y: 0.6668), CGPoint(x: 0.6633, y: 0.65),
        CGPoint(x: 0.6151, y: 0.6519), CGPoint(x: 0.608, y: 0.6553),
        CGPoint(x: 0.6145, y: 0.6744), CGPoint(x: 0.6112, y: 0.6773),
        CGPoint(x: 0.5857, y: 0.6775), CGPoint(x: 0.5727, y: 0.6659),
        CGPoint(x: 0.5576, y: 0.6687), CGPoint(x: 0.545, y: 0.6636),
        CGPoint(x: 0.5197, y: 0.6702), CGPoint(x: 0.4772, y: 0.7065),
        CGPoint(x: 0.4731, y: 0.7315), CGPoint(x: 0.4772, y: 0.7495),
        CGPoint(x: 0.4705, y: 0.7502), CGPoint(x: 0.4447, y: 0.7385),
        CGPoint(x: 0.436, y: 0.7128), CGPoint(x: 0.4111, y: 0.6724),
        CGPoint(x: 0.3989, y: 0.6637), CGPoint(x: 0.3847, y: 0.6641),
        CGPoint(x: 0.3738, y: 0.6814), CGPoint(x: 0.3594, y: 0.6749),
        CGPoint(x: 0.3505, y: 0.6682), CGPoint(x: 0.3404, y: 0.6447),
        CGPoint(x: 0.3149, y: 0.6203), CGPoint(x: 0.2849, y: 0.6203),
        CGPoint(x: 0.2849, y: 0.6294), CGPoint(x: 0.2367, y: 0.6295),
        CGPoint(x: 0.171, y: 0.6034), CGPoint(x: 0.1727, y: 0.5991),
        CGPoint(x: 0.131, y: 0.6032), CGPoint(x: 0.128, y: 0.5919),
        CGPoint(x: 0.1068, y: 0.5704), CGPoint(x: 0.0704, y: 0.5576),
        CGPoint(x: 0.0683, y: 0.5456), CGPoint(x: 0.0515, y: 0.5236),
        CGPoint(x: 0.0377, y: 0.488), CGPoint(x: 0.0166, y: 0.4623),
        CGPoint(x: 0.0142, y: 0.4444), CGPoint(x: 0.005, y: 0.4324),
        CGPoint(x: 0.0082, y: 0.3954), CGPoint(x: 0.0027, y: 0.3786),
        CGPoint(x: 0.0137, y: 0.318), CGPoint(x: 0.0105, y: 0.2886),
        CGPoint(x: 0.0, y: 0.2596), CGPoint(x: 0.0021, y: 0.2553),
        CGPoint(x: 0.0272, y: 0.2628), CGPoint(x: 0.0364, y: 0.2835),
        CGPoint(x: 0.0407, y: 0.2777), CGPoint(x: 0.032, y: 0.2417),
        CGPoint(x: 0.5116, y: 0.2417), CGPoint(x: 0.5116, y: 0.2333),
        CGPoint(x: 0.5175, y: 0.2332),
    ]
}
