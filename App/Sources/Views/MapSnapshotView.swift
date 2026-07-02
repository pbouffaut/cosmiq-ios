import CoreLocation
import MapKit
import SwiftUI

/// Static, pre-rendered map preview. A live MKMapView inside a scrolling list
/// costs a Metal layer, gesture arbitration and Maps telemetry per row; a
/// snapshot is just an image. The region is centered on the coordinate, so the
/// flag overlay sits at the center.
struct MapSnapshotView: View {
    let latitude: Double
    let longitude: Double
    var height: CGFloat = 180
    var hybrid = true

    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.oceanDeep.opacity(0.15)
                    ProgressView()
                }
            }
            .frame(width: geometry.size.width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                Image(systemName: "flag.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .shadow(radius: 2)
                    .offset(y: -12) // flagpole base on the spot
            }
            .task(id: taskKey(width: geometry.size.width)) {
                await snapshot(width: geometry.size.width)
            }
        }
        .frame(height: height)
    }

    private func taskKey(width: CGFloat) -> String {
        "\(latitude),\(longitude),\(Int(width)),\(hybrid)"
    }

    private func snapshot(width: CGFloat) async {
        guard width > 0 else { return }
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
        )
        options.size = CGSize(width: width, height: height)
        options.preferredConfiguration = hybrid
            ? MKHybridMapConfiguration()
            : MKStandardMapConfiguration()
        image = try? await MKMapSnapshotter(options: options).start().image
    }
}
