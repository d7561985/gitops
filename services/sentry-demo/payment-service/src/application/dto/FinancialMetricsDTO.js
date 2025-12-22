/**
 * Track Financial Metrics Request DTO
 * @typedef {Object} TrackFinancialMetricsRequest
 * @property {string} scenario - 'normal' | 'payment_failure_spike' | 'revenue_anomaly'
 */

/**
 * Track Financial Metrics Response DTO
 * @typedef {Object} TrackFinancialMetricsResponse
 * @property {string} status
 * @property {Object.<string, number>} metrics
 */

/**
 * Create TrackFinancialMetricsRequest
 * @param {Object} data
 * @returns {TrackFinancialMetricsRequest}
 */
function createTrackMetricsRequest(data) {
  return {
    scenario: data.scenario || 'normal'
  };
}

/**
 * Create TrackFinancialMetricsResponse
 * @param {Object} data
 * @returns {TrackFinancialMetricsResponse}
 */
function createTrackMetricsResponse({ status, metrics = {} }) {
  return { status, metrics };
}

module.exports = {
  createTrackMetricsRequest,
  createTrackMetricsResponse
};
