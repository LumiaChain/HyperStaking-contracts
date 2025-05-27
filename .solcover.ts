module.exports = {
  skipFiles: ["test", "external"],
  mocha: {
    grep: "@skip-on-coverage", // Find everything with this tag
    invert: true,              // Run the grep's inverse set.
    enableTimeouts: false,
    timeout: 0
  }
};
