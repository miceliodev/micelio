fn main() {
    let proto_dir = "../build/protocols";
    let virtual_proto = format!("{proto_dir}/hif_v1.proto");

    println!("cargo:rerun-if-changed={virtual_proto}");

    tonic_build::configure()
        .build_client(false)
        .build_server(false)
        .compile_protos(&[virtual_proto], &[proto_dir])
        .expect("failed to compile hif v1 protobuf contracts");
}
