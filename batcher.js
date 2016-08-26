const sparks = new WeakMap();
export default class Batcher {
  get config() {
    return this.spark.config;
  }

  get logger() {
    return this.spark.logger;
  }

  get spark() {
    return sparks.get(this);
  }

  constructor(spark) {

  }

  enqueue(item) {

  }

  submitRequest() {
    this.request()
      .then((res) => this.acceptResponse(res));
  }

  acceptResponse() {

  }
}
