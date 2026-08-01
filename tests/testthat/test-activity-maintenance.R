source_activity_maintenance <- function() {
  path <- file.path("R", "ingestion", "reconcile_activities.R")
  if (!file.exists(path)) path <- file.path("..", "..", path)
  source(path)
}
source_activity_maintenance()

activity_fixture <- function(id, payload) data.frame(activity_id = id, raw_payload = payload)
existing_fixture <- function(ids, payloads, details = "SUCCESS", streams = "SUCCESS", laps = "SUCCESS") data.frame(activity_id = ids, raw_payload = payloads, start_datetime_utc = Sys.time(), details_status = details, stream_status = streams, laps_status = laps)

testthat::test_that("configured activity windows select the correct modes", {
  config <- list(ingestion = list(activity_refresh_days=30, activity_hygiene_days=365, activity_backfill_days=8000))
  testthat::expect_equal(activity_ingestion_mode(config,"scheduled")$refresh_days,30L)
  testthat::expect_equal(activity_ingestion_mode(config,"hygiene")$refresh_days,365L)
  annual <- activity_ingestion_mode(config,"activity_backfill")
  testthat::expect_equal(annual$refresh_days,8000L)
  testthat::expect_true(annual$suppress_achievement_notifications)
})

testthat::test_that("repository configuration retains the three authoritative windows", {
  root <- if (file.exists("config/platform.yml")) "." else file.path("..","..")
  config <- yaml::read_yaml(file.path(root,"config/platform.yml"))
  testthat::expect_identical(unlist(config$ingestion[c("activity_refresh_days","activity_hygiene_days","activity_backfill_days")],use.names=FALSE),c(30L,365L,8000L))
})

testthat::test_that("payload comparison ignores JSON member order but detects changes", {
  testthat::expect_false(activity_payload_changed('{"id":1,"name":"Ride"}','{"name":"Ride","id":1}'))
  testthat::expect_true(activity_payload_changed('{"id":1,"name":"Ride"}','{"id":1,"name":"Renamed"}'))
})

testthat::test_that("reconciliation classifies new changed unchanged and missing", {
  incoming <- data.frame(activity_id=c("1","2","4"),raw_payload=c('{"id":1,"name":"same"}','{"id":2,"name":"new"}','{"id":4,"name":"recovered"}'))
  existing <- existing_fixture(c("1","2","3"),c('{"name":"same","id":1}','{"id":2,"name":"old"}','{"id":3,"name":"missing"}'))
  result <- classify_activity_summaries(incoming,existing)
  statuses <- stats::setNames(result$reconciliation_status,result$activity_id)
  testthat::expect_equal(unname(statuses[c("1","2","3","4")]),c("UNCHANGED","CHANGED","MISSING","NEW"))
})

testthat::test_that("only new changed or incomplete activities request child repair", {
  incoming <- data.frame(activity_id=c("1","2"),raw_payload=c('{"id":1}','{"id":2}'))
  existing <- existing_fixture(c("1","2"),c('{"id":1}','{"id":2}'),details=c("SUCCESS","PENDING"),streams=c("SUCCESS","SUCCESS"),laps=c("SUCCESS","SUCCESS"))
  result <- classify_activity_summaries(incoming,existing)
  testthat::expect_equal(result$child_status,c("COMPLETE","INCOMPLETE"))
  testthat::expect_equal(result$details_repair_required,c(0L,1L))
  repeated <- classify_activity_summaries(incoming,existing)
  testthat::expect_equal(repeated,result)
})

testthat::test_that("failed child coverage remains explicitly repairable", {
  incoming <- data.frame(activity_id="1",raw_payload='{"id":1}')
  existing <- existing_fixture("1",'{"id":1}',streams="FAILED")
  result <- classify_activity_summaries(incoming,existing)
  testthat::expect_equal(result$child_status,"FAILED")
  testthat::expect_equal(result$streams_repair_required,1L)
})

testthat::test_that("run lock uses one cross-mode advisory lock", {
  path <- file.path("R","utils","platform_run_lock.R"); if (!file.exists(path)) path <- file.path("..","..",path)
  text <- paste(readLines(path),collapse="\n")
  testthat::expect_match(text,"cycling-platform-exclusive-run",fixed=TRUE)
  testthat::expect_match(text,"GET_LOCK",fixed=TRUE)
})

testthat::test_that("Silver activity publication is constrained to staged affected IDs", {
  root <- if (file.exists("sql/silver/020_transform_activities.sql")) "." else file.path("..","..")
  sql <- paste(readLines(file.path(root,"sql/silver/020_transform_activities.sql")),collapse="\n")
  testthat::expect_false(grepl("TRUNCATE TABLE cycling_platform_silver.activities",sql,fixed=TRUE))
  testthat::expect_match(sql,"INNER JOIN activity_refresh_ids",fixed=TRUE)
})
