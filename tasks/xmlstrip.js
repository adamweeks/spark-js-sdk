'use strict';

var fs = require('fs');
var parser = require('xml2json');
var path = require('path');
var set = require('lodash.set');

module.exports = function(grunt) {
  grunt.registerMultiTask('xmlstrip', 'Remove the specified node from an xml document', function() {
    var options = this.options();
    if (!options.nodes) {
      throw new Error('options.node is required');
    }

    this.files.forEach(function(file) {
      if (fs.statSync(file.src[0]).isDirectory()) {
        return;
      }

      var xml = grunt.file.read(file.src[0]);
      var json = parser.toJson(xml, {
        object: true
      });
      options.nodes.forEach(function(node) {
        set(json, node, undefined);
      });
      delete json.testsuite['system-out'];
      var newXml = parser.toXml(json);
      console.log(require('util').inspect(file, { depth: null }));
      grunt.file.write(path.join(file.orig.cwd, file.dest), newXml);
    });
  });
};
