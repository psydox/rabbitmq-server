load("@rules_erlang//:erlang_bytecode2.bzl", "erlang_bytecode")
load("@rules_erlang//:filegroup.bzl", "filegroup")

def all_beam_files(name = "all_beam_files"):
    filegroup(
        name = "beam_files",
        srcs = [":other_beam"],
    )
    erlang_bytecode(
        name = "other_beam",
        srcs = [
            "src/rabbit_shovel_prometheus_app.erl",
            "src/rabbit_shovel_prometheus_collector.erl",
            "src/rabbit_shovel_prometheus_sup.erl",
        ],
        hdrs = [":public_and_private_hdrs"],
        app_name = "rabbitmq_shovel_prometheus",
        dest = "ebin",
        erlc_opts = "//:erlc_opts",
        deps = ["@prometheus//:erlang_app"],
    )

def all_srcs(name = "all_srcs"):
    filegroup(
        name = "all_srcs",
        srcs = [":public_and_private_hdrs", ":srcs"],
    )
    filegroup(
        name = "public_and_private_hdrs",
        srcs = [":private_hdrs", ":public_hdrs"],
    )

    filegroup(
        name = "priv",
    )

    filegroup(
        name = "srcs",
        srcs = [
            "src/rabbit_shovel_prometheus_app.erl",
            "src/rabbit_shovel_prometheus_collector.erl",
            "src/rabbit_shovel_prometheus_sup.erl",
        ],
    )
    filegroup(
        name = "private_hdrs",
    )
    filegroup(
        name = "public_hdrs",
    )
    filegroup(
        name = "license_files",
        srcs = [
            "LICENSE",
            "LICENSE-MPL-RabbitMQ",
        ],
    )

def all_test_beam_files(name = "all_test_beam_files"):
    filegroup(
        name = "test_beam_files",
        testonly = True,
        srcs = [":test_other_beam"],
    )
    erlang_bytecode(
        name = "test_other_beam",
        testonly = True,
        srcs = [
            "src/rabbit_shovel_prometheus_app.erl",
            "src/rabbit_shovel_prometheus_collector.erl",
            "src/rabbit_shovel_prometheus_sup.erl",
        ],
        hdrs = [":public_and_private_hdrs"],
        app_name = "rabbitmq_shovel_prometheus",
        dest = "test",
        erlc_opts = "//:test_erlc_opts",
        deps = ["@prometheus//:erlang_app"],
    )

def test_suite_beam_files(name = "test_suite_beam_files"):
    erlang_bytecode(
        name = "prometheus_rabbitmq_shovel_collector_SUITE_beam_files",
        testonly = True,
        srcs = ["test/prometheus_rabbitmq_shovel_collector_SUITE.erl"],
        outs = ["test/prometheus_rabbitmq_shovel_collector_SUITE.beam"],
        app_name = "rabbitmq_shovel_prometheus",
        erlc_opts = "//:test_erlc_opts",
        deps = ["//deps/amqp_client:erlang_app", "@prometheus//:erlang_app"],
    )
