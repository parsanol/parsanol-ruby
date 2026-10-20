// parsanol artifact acceptance harness: parses each corpus doc through
// the compiled PARG artifact (the shipped artifact path).
use parsanol::PargArtifact;
use std::time::Instant;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let corpus_path = &args[1];
    let artifact_path = &args[2];
    let iterations: usize = args[3].parse().expect("iterations");
    let corpus: serde_json::Value =
        serde_json::from_str(&std::fs::read_to_string(corpus_path).unwrap()).unwrap();
    let artifact = PargArtifact::from_path(std::path::Path::new(artifact_path))
        .expect("artifact must verify");

    let mut docs: Vec<(String, String)> = Vec::new();
    if let serde_json::Value::Object(map) = &corpus {
        for (name, text) in map {
            docs.push((name.clone(), text.as_str().unwrap().to_string()));
        }
    }
    // Warmup + acceptance verification.
    for (name, text) in &docs {
        artifact
            .parse_shape("value", text)
            .unwrap_or_else(|e| panic!("{name} failed to parse: {e}"));
    }
    let mut samples: Vec<(String, usize, Vec<f64>)> =
        docs.iter().map(|(n, t)| (n.clone(), t.len(), Vec::new())).collect();
    for _ in 0..iterations {
        for (i, (_, text)) in docs.iter().enumerate() {
            let start = Instant::now();
            let _ = artifact.parse_shape("value", text);
            samples[i].2.push(start.elapsed().as_secs_f64() * 1000.0);
        }
    }
    for (name, bytes, mut times) in samples {
        times.sort_by(|a, b| a.partial_cmp(b).unwrap());
        let median = times[times.len() / 2];
        println!("parsanol-native,{name},{bytes},{iterations},{median:.6}");
    }
}
