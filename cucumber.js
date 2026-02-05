export default {
  default: {
    paths: ["features/*.feature"],
    require: ["features/step_definitions/*.js", "features/support/*.js"],
    format: ["progress-bar", ["html", "out/test/cucumber-report.html"]],
    parallel: 1,
    failFast: false,
  },
};
