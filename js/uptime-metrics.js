(function () {
  function formatNumber(value) {
    return new Intl.NumberFormat().format(Number(value || 0));
  }

  function ratioValue(value) {
    if (value === null || value === undefined || value === "") {
      return null;
    }
    var number = Number(value);
    return Number.isFinite(number) ? number : null;
  }

  function formatRatio(value) {
    var number = ratioValue(value);
    if (number === null) {
      return "n/a";
    }
    return number.toFixed(3).replace(/\.?0+$/, "") + "%";
  }

  function averageRatio(monitors, key) {
    var values = monitors
      .map(function (monitor) {
        return ratioValue((monitor[key] || {}).ratio);
      })
      .filter(function (value) {
        return value !== null;
      });
    if (!values.length) {
      return null;
    }
    return values.reduce(function (sum, value) {
      return sum + value;
    }, 0) / values.length;
  }

  function statusText(statusClass) {
    if (statusClass === "success") {
      return "Operational";
    }
    if (statusClass === "warning") {
      return "Degraded";
    }
    if (statusClass === "danger" || statusClass === "error") {
      return "Down";
    }
    if (statusClass === "muted") {
      return "Paused";
    }
    return statusClass || "Unknown";
  }

  function statusRank(monitor) {
    return monitor.statusClass === "success" ? 1 : 0;
  }

  function addMetric(summary, value, label) {
    var metric = document.createElement("span");
    metric.className = "uptime-metrics__metric";

    var number = document.createElement("strong");
    number.textContent = value;

    var text = document.createElement("span");
    text.textContent = label;

    metric.append(number, text);
    summary.append(metric);
  }

  function addCell(row, text, className) {
    var cell = document.createElement("td");
    if (className) {
      cell.className = className;
    }
    cell.textContent = text;
    row.append(cell);
  }

  function renderStatus(block, message) {
    block.textContent = "";
    var status = document.createElement("span");
    status.className = "user-metrics__status";
    status.textContent = message;
    block.append(status);
  }

  function render(block, payload) {
    var monitors = Array.isArray(payload.data) ? payload.data : [];
    if (!monitors.length) {
      renderStatus(block, "Uptime metrics are not available.");
      return;
    }

    var operational = monitors.filter(function (monitor) {
      return monitor.statusClass === "success";
    }).length;
    var affected = monitors.length - operational;
    var sorted = monitors.slice().sort(function (left, right) {
      return statusRank(left) - statusRank(right) ||
        String(left.name || "").localeCompare(String(right.name || ""));
    });

    block.textContent = "";

    var summary = document.createElement("div");
    summary.className = "uptime-metrics__summary";
    addMetric(summary, affected ? formatNumber(affected) : "All", affected ? "affected monitors" : "systems operational");
    addMetric(summary, formatNumber(operational) + " / " + formatNumber(monitors.length), "monitors up");
    addMetric(summary, formatRatio(averageRatio(monitors, "30dRatio")), "average 30-day uptime");
    addMetric(summary, formatRatio(averageRatio(monitors, "90dRatio")), "average 90-day uptime");
    block.append(summary);

    var wrapper = document.createElement("div");
    wrapper.className = "user-metrics__table-wrapper";

    var table = document.createElement("table");
    table.className = "user-metrics__table uptime-metrics__table td-initial";

    var head = document.createElement("thead");
    var headRow = document.createElement("tr");
    ["Monitor", "Type", "Status", "30-day uptime", "90-day uptime", "Latest downtime"].forEach(function (text, index) {
      var th = document.createElement("th");
      th.textContent = text;
      th.scope = "col";
      if (index === 3 || index === 4) {
        th.className = "user-metrics__num";
      }
      headRow.append(th);
    });
    head.append(headRow);
    table.append(head);

    var body = document.createElement("tbody");
    sorted.forEach(function (monitor) {
      var row = document.createElement("tr");

      var nameCell = document.createElement("th");
      nameCell.scope = "row";
      nameCell.textContent = monitor.name || "Unknown monitor";
      row.append(nameCell);

      addCell(row, monitor.type || "");

      var statusCell = document.createElement("td");
      var badge = document.createElement("span");
      badge.className = "uptime-metrics__badge uptime-metrics__badge--" + (monitor.statusClass || "unknown");
      badge.textContent = statusText(monitor.statusClass);
      statusCell.append(badge);
      row.append(statusCell);

      addCell(row, formatRatio((monitor["30dRatio"] || {}).ratio), "user-metrics__num");
      addCell(row, formatRatio((monitor["90dRatio"] || {}).ratio), "user-metrics__num");
      addCell(row, monitor.lastDowntime && monitor.lastDowntime.date
        ? monitor.lastDowntime.date
        : "No downtime recorded");

      body.append(row);
    });
    table.append(body);
    wrapper.append(table);
    block.append(wrapper);
  }

  var blocks = document.querySelectorAll("[data-uptime-metrics-url]");
  if (!blocks.length) {
    return;
  }

  fetch(blocks[0].dataset.uptimeMetricsUrl, { credentials: "omit" })
    .then(function (response) {
      if (!response.ok) {
        throw new Error("Uptime metrics request failed: " + response.status);
      }
      return response.json();
    })
    .then(function (payload) {
      blocks.forEach(function (block) {
        render(block, payload);
      });
    })
    .catch(function () {
      blocks.forEach(function (block) {
        renderStatus(block, "Uptime metrics could not be loaded.");
      });
    });
}());
