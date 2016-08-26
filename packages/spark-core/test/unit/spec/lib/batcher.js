/**!
 *
 * Copyright (c) 2015-2016 Cisco Systems, Inc. See LICENSE file.
 */

import lolex from 'lolex';
import {assert} from '@ciscospark/test-helper-chai';
import MockSpark from '@ciscospark/test-helper-mock-spark';
import sinon from '@ciscospark/test-helper-sinon';
import {Batcher} from '../../..';

describe(`spark-core`, () => {
  describe(`Batcher`, () => {
    class MockBatcher extends Batcher {}

    let spark;
    let batcher;
    beforeEach(() => {
      spark = new MockSpark({});
      spark.request.onCall(0).returns(0);
      spark.request.onCall(1).returns(1);
      spark.request.onCall(2).returns(2);
      batcher = new MockBatcher(spark);
    });

    let clock;
    beforeEach(() => {
      clock = lolex.install(Date.now());
    });

    afterEach(() => {
      clock.uninstall();
    });

    describe(`#request()`, () => {
      it(`coalesces requests made in a short time period into a single request`, () => {
        const promises = [];
        promises.push(batcher.request());
        assert.notCalled(spark.request);
        promises.push(batcher.request());
        assert.notCalled(spark.request);
        promises.push(batcher.request());
        assert.notCalled(spark.request);

        clock.tick(1);
        assert.calledOnce(spark.request);
        return assert.isFulfilled(Promise.all(promises))
          .then(([r0, r1, r2]) => {
            assert.equal(r0.body, 0);
            assert.equal(r1.body, 1);
            assert.equal(r2.body, 2);
            clock.tick(500);
            assert.calledOnce(spark.request);
          });
      });

    });
  });
});
