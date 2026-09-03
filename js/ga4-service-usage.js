(function () {
  function formatNumber(value) {
    return new Intl.NumberFormat().format(Number(value || 0));
  }

  function formatDate(value) {
    if (!value) {
      return "";
    }
    var date = new Date(value);
    if (Number.isNaN(date.getTime())) {
      return "";
    }
    return date.toLocaleDateString(undefined, {
      year: "numeric",
      month: "short",
      day: "numeric",
      timeZone: "UTC"
    });
  }

  function appendIntro(block, segments) {
    var text = String(block.dataset.ga4ServiceUsageIntro || "").trim();
    if (!text) {
      return;
    }

    var intro = document.createElement("p");
    intro.textContent = text;

    if (segments && segments.length === 1) {
      var trackingDate = formatDate(segments[0].trackingStartDate);
      intro.textContent += trackingDate
        ? " Tracking started on " + trackingDate + "."
        : " A tracking start date has not yet been recorded.";
    } else if (segments && segments.length > 1) {
      var trackingDates = segments.map(function (segment) {
        return (segment.name || segment.id) + ": " +
          (formatDate(segment.trackingStartDate) || "not yet recorded");
      });
      intro.textContent += " Tracking started: " + trackingDates.join("; ") + ".";
    }

    block.append(intro);
  }

  function renderStatus(block, message) {
    block.textContent = "";
    appendIntro(block);
    var status = document.createElement("span");
    status.className = "user-metrics__status";
    status.textContent = message;
    block.append(status);
  }

  function requestedIds(block) {
    return String(block.dataset.ga4ServiceUsageIds || "")
      .split(",")
      .map(function (id) { return id.trim(); })
      .filter(Boolean);
  }

  function selectedSegments(data, ids) {
    var segments = Array.isArray(data.segments) ? data.segments : [];
    if (!ids.length) {
      return segments;
    }
    var byId = new Map(segments.map(function (segment) {
      return [segment.id, segment];
    }));
    return ids.map(function (id) { return byId.get(id); }).filter(Boolean);
  }

  function addNumericCell(row, value) {
    var cell = document.createElement("td");
    cell.className = "user-metrics__num";
    cell.textContent = formatNumber(value);
    row.append(cell);
  }

  function render(block, data) {
    if (data.unavailable) {
      renderStatus(block, "Service usage statistics are not available in this build.");
      return;
    }

    var ids = requestedIds(block);
    var segments = selectedSegments(data, ids);
    if (!segments.length) {
      renderStatus(block, "Service usage statistics are not configured for this build.");
      return;
    }

    var periodDays = data.periodDays || 30;
    block.textContent = "";
    appendIntro(block, segments);

    var details = document.createElement("p");
    details.className = "user-metrics__details";
    details.textContent = "Source: " + (data.source || "Google Analytics") +
      " · last " + periodDays + " days";
    var generatedAt = formatDate(data.generatedAt);
    if (generatedAt) {
      details.textContent += " · updated " + generatedAt;
    }
    block.append(details);

    var wrapper = document.createElement("div");
    wrapper.className = "user-metrics__table-wrapper";

    var table = document.createElement("table");
    table.className = "user-metrics__table td-initial";

    var head = document.createElement("thead");
    var headRow = document.createElement("tr");
    [
      "Service",
      "Users to date",
      "Users (" + periodDays + " days)"
    ].forEach(function (text, index) {
      var th = document.createElement("th");
      th.textContent = text;
      th.scope = "col";
      if (index > 0 && index < 3) {
        th.className = "user-metrics__num";
      }
      headRow.append(th);
    });
    head.append(headRow);
    table.append(head);

    var body = document.createElement("tbody");
    segments.forEach(function (segment) {
      var row = document.createElement("tr");

      var serviceCell = document.createElement("th");
      serviceCell.scope = "row";
      if (segment.url) {
        var link = document.createElement("a");
        link.href = segment.url;
        link.target = "_blank";
        link.rel = "noopener noreferrer";
        link.textContent = segment.name || segment.id;
        serviceCell.append(link);
      } else {
        serviceCell.textContent = segment.name || segment.id;
      }
      row.append(serviceCell);

      addNumericCell(row, segment.totalUsers);
      addNumericCell(row, segment.periodUsers);

      body.append(row);
    });
    table.append(body);
    wrapper.append(table);
    block.append(wrapper);
  }

  function init() {
    var blocks = document.querySelectorAll("[data-ga4-service-usage-url]");
    if (!blocks.length) {
      return;
    }

    fetch(blocks[0].dataset.ga4ServiceUsageUrl, { credentials: "same-origin" })
      .then(function (response) {
        if (!response.ok) {
          throw new Error("Service usage statistics request failed: " + response.status);
        }
        return response.json();
      })
      .then(function (data) {
        blocks.forEach(function (block) {
          render(block, data);
        });
      })
      .catch(function () {
        blocks.forEach(function (block) {
          renderStatus(block, "Service usage statistics could not be loaded.");
        });
      });
  }

  // The script is emitted next to the first shortcode block, so later blocks
  // on the page have not been parsed yet — wait for the full DOM.
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
}());
