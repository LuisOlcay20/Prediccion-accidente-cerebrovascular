## Librerías

```{r, }
library(tidymodels)
library(tidyverse)
library(rpart.plot)
library(vip)
library(beepr)
library(readr)
library(ranger)
library(skimr)
library(baguette)
library(randomForest)
library(latex2exp)
```

#### Inspeccionamos la estructura de los datos y verificamos si las variables numéricas y categóricas están en el formato correcto.

```{r}
setwd("C:/Users/olcay/Desktop/R studio/Archivo data")
stroke <- read_csv("stroke.csv")
str(stroke)
stroke <- stroke %>%  mutate(gender = factor(gender,levels = c("Male","Female")),
                             hypertension = factor(hypertension, levels = c(1,0)),
                             heart_disease = factor(heart_disease, levels = c(1,0)),
                             ever_married = factor(ever_married, levels = c("Yes","No")),
                             work_type = factor(work_type, levels = c("children","Govt_job","Never_worked","Private","Self-employed")),
                             Residence_type = factor(Residence_type, levels = c("Urban","Rural")),
                             smoking_status = factor(smoking_status, levels = c("formerly smoked", "never smoked","smokes")),
                             stroke = factor(stroke, levels = c(1,0)),
                             bmi = as.numeric(bmi))

str(stroke)
skim(stroke)
```

#### Determinamos el porcentaje de pacientes que no revela status fumador.

```{r, }
stroke %>% dplyr::count(smoking_status) %>% 
  dplyr::mutate(prop = n/sum(n))
```

En general, podemos tratar NAs mediante eliminación o estrategias para imputar valores. Esto dependerá de su importancia en el conjunto de datos:
  
  -   Si la cantidad de NA es insignficante y el conjunto de datos es amplio, deberían eliminarse.

-   Si la cantidad de NA es signficante dentro del conjunto de datos, se podría intentar reemplazarlos por valores como la media, mediana, moda u otros. Más específicamente, considerando que nos referimos a un Decision Tree podríamos modificar el algoritmo para tratar los valores faltantes.

Considerando que no se conoce el status de fumador de un 0,302 porciento de la muestra, trataríamos de alguna forma los NA.

####  Separamos la muestra en un conjunto de entrenamiento con proporción 0.8, estratificando la variable stroke.

```{r}
stroke %>% count(stroke) %>%
  mutate(prop = n/sum(n))

set.seed(120)

#Separamos la muestra
stroke_split <- rsample::initial_split(stroke,
                                       prop = 0.8,
                                       strata = stroke)

stroke_train <- rsample::training(stroke_split)
stroke_test <- rsample::testing(stroke_split)

#Resample data
set.seed(120)
stroke_cv <- rsample::vfold_cv(stroke_train, v=10, strata = stroke)

```

#### d) Ajustamos un árbol de clasificación a la muestra de entrenamiento, considerando los siguientes valores de los hiperparámetros: cost complexity = 0, tree depth = 20 , min n = 15.

```{r}
#Especificación del modelo
stroke_model <- parsnip::decision_tree(
  mode = "classification",
  engine = "rpart",
  cost_complexity = 0,
  tree_depth = 20,
  min_n = 15
)

#Especificación de la receta
stroke_recipe <- recipes::recipe(stroke ~.,data = stroke_train) %>% 
  update_role(id, new_role = "id variable")

stroke_recipe %>% 
  prep() %>% 
  bake(new_data = stroke_train) %>% view()

#Creamos un WF
stroke_wf_large <- workflows::workflow() %>% 
  add_model(stroke_model) %>% 
  add_recipe(stroke_recipe)

#Fit a Model
stroke_wf_fit_large <- stroke_wf_large %>% 
  parsnip::fit(data = stroke_train)

stroke_predictions_large <- stroke_wf_fit_large %>% 
  predict(new_data = stroke_test) %>% 
  dplyr::bind_cols(stroke_test) %>% 
  dplyr::select(stroke, .pred_class)

head(stroke_predictions_large)
```

#### Graficamos el árbol de clasificación obtenido e interpretamos los resultados. Además, mostramos la tasa de error del conjunto test.

```{r}
rpart.plot::prp(stroke_wf_fit_large$fit$fit$fit, type = 0, fallen.leaves = TRUE,
                tweak = 1.3,roundint = FALSE)

#vemos el accurracy del tree
acc_tree_large <- accuracy(
  data = stroke_predictions_large,
  truth = stroke,
  estimate = .pred_class
)
acc_tree_large

#vemos la matriz de confussion
conf_mat_tree_large <- conf_mat(
  data = stroke_predictions_large,
  truth = stroke,
  estimate = .pred_class
)
autoplot(conf_mat_tree_large, "heatmap")
```

A partir del árbol expuesto, se pueden inferir las siguientes conclusiones:
  
  -   La variable más importante a la hora de predecir un stroke es la edad.

-   Una persona que tiene menos de 57 años es poco probable que sufra un stroke.

-   Si una persona tiene más de 75 años, el índice de masa corporal tiene mayor importancia que el promedio de glucosa en la sangre para predecir un stroke.

-   Si una persona tiene menos de 76 años, el promedio de glucosa en la sangre tiene mayor importancia que el índice de masa corporal para predecir un stroke.

Por otra parte, podemos obsevar que el modelo tiene un accuracy de 0.933, lo que quiere decir que logra clasificar correctamente un 93,33% e incorrectamente un 6,7% de las predicciones.

####  Realizamos un 10-fold validación para determinar los valores óptimos de los hiperparámetros: cost complexity() y tree depth(). Para esto utilizamos una grilla regular con el rango de cada hiperparámetro que trae por defecto y utilizamos levels = 5.

```{r}
## Tunning de hiperparametros ##
set.seed(120)
#La receta se mantiene
stroke_recipe <- recipes::recipe(stroke ~.,data = stroke_train) %>% 
  update_role(id, new_role = "id variable")
#Especificación del modelo con hiperparámetros tuneados
stroke_model_tune <- parsnip::decision_tree(
  mode = "classification",
  engine = "rpart",
  cost_complexity = tune(),
  tree_depth = tune(),
  min_n = 15
)

#Creamos un WF con hiperparámetros tuneados
stroke_wf_tune<- workflows::workflow() %>% 
  add_model(stroke_model_tune) %>% 
  add_recipe(stroke_recipe)


#Vemos los rangos que traen los hiperparametros por defecto
cost_complexity()
tree_depth()
min_n()

#Establecemos la grilla de partida
start_grid <-  grid_regular(cost_complexity (),
                            tree_depth (),
                            levels = 5)
start_grid

#Para correr multiples modelos
parallel::detectCores()
cl <- parallel::makeCluster(8)
doParallel::registerDoParallel(cl)

#Buscamos la combinación óptima de hiperparámetros
tree_tuning <- stroke_wf_tune %>% 
  tune_grid(resamples = stroke_cv,
            grid = start_grid)
autoplot(tree_tuning)
parallel::stopCluster(cl)

#Observamos los conjuntos con mejor AUC y seleccionamos el mejor
tree_tuning %>% show_best('roc_auc')
best_parameters <- tree_tuning %>% 
  select_best(metric = 'roc_auc')
best_parameters

```

Observamos que los valores óptimos de los hiperparámetros son:
  
  -   cost_complexity= 1e-10
-   tree_depth = 8

####  Con los valores encontrados, podamos el árbol y calculamos la tasa de error del conjunto test. Además, gráficamos e interpretamos.

```{r}

#WF final
final_stroke_wf <- stroke_wf_tune %>% 
  finalize_workflow(best_parameters)
final_stroke_wf

#Fit a Model
stroke_fit_prune <- final_stroke_wf %>% 
  fit(stroke_train)

stroke_predictions_prune <- stroke_fit_prune %>% 
  predict(new_data = stroke_test) %>% 
  dplyr::bind_cols(stroke_test) %>% 
  dplyr::select(stroke, .pred_class)

head(stroke_predictions_prune)

#graficamos

rpart.plot::prp(stroke_fit_prune$fit$fit$fit, type = 0, fallen.leaves = TRUE,
                tweak = 1.3,roundint = FALSE)

#vemos el accurracy del tree
acc_tree_prune <- accuracy(
  data = stroke_predictions_prune,
  truth = stroke,
  estimate = .pred_class
)
acc_tree_prune

#vemos la matriz de confussion
conf_mat_tree_prune <- conf_mat(
  data = stroke_predictions_prune,
  truth = stroke,
  estimate = .pred_class
)
autoplot(conf_mat_tree_prune, "heatmap")
```

Teniendo en consideración que el árbol podado posee los siguientes hiperparámetros:
  
  -   cost_complexity= 1e-10
-   tree_depth = 8
-   min_n = 15 (mismo que el árbol original)

Sabemos que el cost_complexity es un método de penalización (Loss Penalty). El grado de penalización se encuentra por medio del tunning del hiperparámetro alfa. Cuando alfa = 0, no existe penalización y el árbol podado es parecido al original. A medida que aumenta alfa, la penalización es mayor y los árboles podados son más pequeños que los originales. Por consiguiente, al tener un alfa cercano a 0, la penalización es muy baja. Por otra parte, el tree_depth baja de 20 a 8,lo que significa que el árbol ahora puede tener un máxima profundidad de 8. Si bien, el cambio en este hiperparámetro es significativo, el árbol original ya estaba utilizando una profundidad parecida a pesar de tener la libertad de utilizar una profundidad de hasta 20.

Por lo tanto, el árbol podado es estructuralmente igual al árbol orginal, esta condición se conoce como correlación entre los árboles y se da cuando el decision tree es un modelo que logra percibir correctamente la relación entre los predictores y la respuesta, lo que genera una correlación entre los predictores de ambos árboles (correlación entre sus predicciones). Por otra parte, el árbol podado tiene menor profundidad, hecho que hace que el árbol podado sea más corto que el original. Todo esto se traduce en que el árbol podado sea más preciso a la hora de clasificar, obteniendo un acurracy de 93,6% y, como consecuencia, clasifique incorrectamente un 6,4% de las predicciones.

Más específicamente, del gráfico del tunning que aparece en f) podemos observar como el pequeño aumento de acurracy del árbol podado se debe principalmente a una disminución del tree_depth y no del cost_complexity, pues recién a partir de un cost_complexity similiar a 1e-3, se comienzan a observar mejoras en el acurracy, pero a costa de una disminución en el roc_auc.

####  Calculamos la importancia de la variable de cada predictor para el ́arbol podado.

```{r}
#Importancia de la variables
stroke_fit_prune <- stroke_fit_prune %>% 
  pull_workflow_fit()

vip(stroke_fit_prune)

```

De los resultados podemos notar que las variables más importantes para el arbol podado son la edad, el promedio de glucosa en la sangre y el índice del masa corporal.

####  A continuación, se construye un modelo de clasificación utilizando el enfoque del bagging tree

```{r}
set.seed(120)
doParallel::registerDoParallel(parallel::makeCluster(8))

#Utilizamos la misma receta
stroke_recipe <- recipes::recipe(stroke ~., data = stroke_train) %>%
  update_role(id, new_role = "id variable")

#Especificación del modelo con hiperparámetros tuneados
stroke_model_bag <- bag_tree(
  mode = "classification",
  engine = "rpart",
  cost_complexity = tune(),
  tree_depth = tune(),
  min_n = tune()) 


#Creamos un wf
stroke_wf_bag <- workflows::workflow() %>% 
  add_model(stroke_model_bag) %>% 
  add_recipe(stroke_recipe)

stroke_wf_bag


## tuneamos los hiperparametros ##

#Establecemos la grilla de partida
start_grid_bag <-  grid_regular(cost_complexity (),
                                tree_depth (),
                                min_n (),
                                levels = 3)
start_grid

#Buscamos la combinación óptima de hiperparámetros
tree_tuning_bag <- stroke_wf_bag %>% 
  tune_grid(resamples = stroke_cv,
            grid = start_grid_bag)


#Observamos los conjuntos con mejor AUC y seleccionamos el mejor
tree_tuning_bag %>% show_best(metric = 'roc_auc')
best_parameters_bag <- tree_tuning_bag %>% 
  select_best(metric = 'roc_auc')
best_parameters_bag
autoplot(tree_tuning_bag)
#WF final
final_stroke_wf_bag <- stroke_wf_bag %>% 
  finalize_workflow(best_parameters_bag)
final_stroke_wf_bag

#Fit a Model
stroke_fit_bag <- final_stroke_wf_bag %>% 
  fit(stroke_train)

stroke_predictions_bag <- stroke_fit_bag %>% 
  predict(new_data = stroke_test) %>% 
  dplyr::bind_cols(stroke_test) %>% 
  dplyr::select(stroke, .pred_class)

head(stroke_predictions_bag)

#vemos el accurracy del tree
acc_tree_bag <- accuracy(
  data = stroke_predictions_bag,
  truth = stroke,
  estimate = .pred_class
)
acc_tree_bag

#vemos la matriz de confussion
conf_mat_tree_bag <- conf_mat(
  data = stroke_predictions_bag,
  truth = stroke,
  estimate = .pred_class
)
autoplot(conf_mat_tree_bag, "heatmap")

#Variables importantes
stroke_fit_bag
```

Teniendo en consideración que el modelo posee los siguientes hiperparámetros:
  
  -   cost_complexity= 1e-10 (mismo que el árbol podado)
-   tree_depth = 8 (mismo que el árbol podado)
-   min_n = 21

A través del gráfico podemos observar que por lo general, combinaciones de hiperparámetros que contengan un tree_depth bajo nos llevará a obtener altos valores de acurracy, pero bajos valores de roc_auc. Por otra parte, podemos observar que la combinación de hiperparámetros obtenidos a través del tunning nos ofrece un alto valor de roc_auc y un acurracy de 94,2%, lo que significa que el modelo clasifica erróneamente un 5,8% de las predicciones.

El aumento en acurracy en comparación a los otros 2 árboles se debe gracias a que el bootstrap aplicado permite reducir la varianza, siempre y cuando los modelos agregados no se correlacionen. Como existe un pequeño aumento en acurracy, podemos inferir que la correlación entre los modelos agregados es alta. Si bien al utilizar bagging se mejora la predicción de un decision tree, se pierde la interpretabilidad de este. Sin embargo, al observar la matriz de confusión nos damos cuenta de que está prediciendo todos los valores como 0 y ninguno como 1 (stroke), a diferencia del modelo anterior. Por lo tanto, es peor que el modelo anterior.

A continuación, se utilizan más métricas en el tunning:
  
  ```{r}
#Buscamos la combinación óptima de hiperparámetros
tree_tuning_bag <- stroke_wf_bag %>% 
  tune_grid(resamples = stroke_cv,
            grid = start_grid_bag,
            metrics = metric_set(recall,precision,roc_auc))


#Utilizamos precision
best_parameters_bag <- tree_tuning_bag %>% 
  select_best(metric = 'recall')
best_parameters_bag

#WF final
final_stroke_wf_bag <- stroke_wf_bag %>% 
  finalize_workflow(best_parameters_bag)
final_stroke_wf_bag

#Fit a Model
stroke_fit_bag <- final_stroke_wf_bag %>% 
  fit(stroke_train)

stroke_predictions_bag <- stroke_fit_bag %>% 
  predict(new_data = stroke_test) %>% 
  dplyr::bind_cols(stroke_test) %>% 
  dplyr::select(stroke, .pred_class)

head(stroke_predictions_bag)

#vemos el accurracy del tree
acc_tree_bag <- accuracy(
  data = stroke_predictions_bag,
  truth = stroke,
  estimate = .pred_class
)
acc_tree_bag

#vemos la matriz de confussion
conf_mat_tree_bag <- conf_mat(
  data = stroke_predictions_bag,
  truth = stroke,
  estimate = .pred_class
)
autoplot(conf_mat_tree_bag, "heatmap")

#Variables importantes
stroke_fit_bag
parallel::stopCluster(parallel::makeCluster(8))
```

Con recall como métrica, se logra que el modelo empiece a predecir strokes, pero cae la accuracy (con precision como métrica, el modelo queda prácticamente igual que con roc_auc).

Finalmente, no es posible calcular gráficamente la importancia de cada variable para un modelo bagging usando tidymodels.

####  A continuación, se construye un modelo de clasificación utilizando Random Forests

```{r}
doParallel::registerDoParallel(parallel::makeCluster(8))
#Tratamos los NA
summary(stroke)
stroke_imputed <- tibble::as_tibble(
  randomForest::rfImpute(stroke ~., ntree = 200, iter = 5, data = stroke))

set.seed(120)
#Split nuevos datos
stroke_imputed_split <- rsample::initial_split(stroke_imputed,
                                               prop = 0.8,
                                               strata = stroke)

stroke_imputed_train <- rsample::training(stroke_imputed_split)
stroke_imputed_test <- rsample::testing(stroke_imputed_split)
stroke_imputed_cv <- rsample::vfold_cv(stroke_imputed_train, v=10, strata = stroke)


#Receta
stroke_imputed_recipe <- recipes::recipe(stroke ~., data = stroke_imputed_train) %>%
  update_role(id, new_role = "id variable")

#Modelo
stroke_model_rf <- parsnip::rand_forest(mtry = tune(),
                                        trees = tune(),
                                        min_n = tune()) %>% 
  set_engine('ranger', importance = "impurity") %>% 
  set_mode('classification')

#WF
stroke_wf_rf <- workflows::workflow() %>% 
  add_model(stroke_model_rf) %>% 
  add_recipe(stroke_imputed_recipe)

#Mtry no esta completo porque no sabemos el total de variables predictoras
mtry()

#Creamos un grilla de partida
start_grid_rf <- grid_regular(
  mtry (range = c(4L,10L)),
  trees(),
  min_n(),
  levels = 3)

start_grid_rf

#Buscamos la combinacion optima
tree_tuning_rf <- stroke_wf_rf %>% 
  tune_grid(resamples = stroke_imputed_cv,
            grid = start_grid_rf)
autoplot(tree_tuning_rf)

#Observamos los conjuntos con mejor AUC y seleccionamos el mejor
tree_tuning_rf %>% show_best(metric = 'roc_auc')
best_parameters_rf <- tree_tuning_rf %>% 
  select_best(metric = 'roc_auc')
best_parameters_rf

#WF final
stroke_final_wf_rf <- stroke_wf_rf %>% 
  finalize_workflow(best_parameters_rf)

stroke_final_wf_rf

#Fit a Model
stroke_fit_rf <- stroke_final_wf_rf %>% 
  fit(stroke_imputed_train)

stroke_predictions_rf <- stroke_fit_rf %>% 
  predict(new_data = stroke_imputed_test) %>% 
  dplyr::bind_cols(stroke_imputed_test) %>% 
  dplyr::select(stroke, .pred_class)

head(stroke_predictions_rf)

#vemos el accurracy del tree
acc_tree_rf <- accuracy(
  data = stroke_predictions_rf,
  truth = stroke,
  estimate = .pred_class
)
acc_tree_rf

#vemos la matriz de confussion
conf_mat_tree_rf <- conf_mat(
  data = stroke_predictions_rf,
  truth = stroke,
  estimate = .pred_class
)
autoplot(conf_mat_tree_rf, "heatmap")

#Variables importantes
stroke_fit_rf <- stroke_fit_rf %>% 
  pull_workflow_fit()
vip(stroke_fit_rf)

```

Debido a que el modelo de Random Forest realiza una selección aleatoria de características, los métodos tradicionales de NAs implementados por los decisions trees no aplican. Por consiguiente, imputamos los datos a través del comando "rfImpute" que para predictores continuos, el valor imputado es el promedio ponderado de las observaciones que no faltan, en donde los pesos son las proximidades. Y, para predictores categóricos, el valor imputado es la categoría con la mayor proximidad promedio.

El modelo posee los siguientes hiperparámetros:
  
  -   mtry = 4
-   trees = 2000
-   min_n = 40

A través de los gráficos podemos observar como independiente al valor del min_n y ante un alto número de trees, la importancia del número de predictores seleccionados (mtry) en el valor del acurracy es casi nula. Sin embargo, cuando solo se utiliza solo 1 tree, el mtry comienza a tener implicancia en el acurracy (considerando el hecho de que al utilizar solo 1 tree, de por sí el acurracy disminuye).

Como se mencionó, el método del bagging tiene el problema de la alta correlación entre sus árboles. Random forest logra decorrelacionar los árboles por medio una selección aleatoria de m predictores (mtry) antes evaluar cada nodo de decisión. Por consiguiente, ciertos nodos de decisión utilizarán predictores diferentes al predictor influyente y como consecuencia se debería lograr una disminución de la varianza, por ende, un mayor acurracy.

Como se puede ver, al ajustar según la métrica de roc_auc se obtiene el mismo accuracy y resultados que en el caso de bagging con una accuracy de 94,2% y un 5,8% de error de clasificación. Además, tampoco predice strokes.Esto nos indica que es posible que no sea la mejor métrica para este caso.

A continuación, se utilizan más métricas en el tunning:
  
  ```{r}
#Buscamos la combinacion optima
tree_tuning_rf <- stroke_wf_rf %>% 
  tune_grid(resamples = stroke_imputed_cv,
            grid = start_grid_rf,
            metrics = metric_set(precision,recall,roc_auc))

#Observamos los conjuntos con mejor AUC y seleccionamos el mejor
tree_tuning_rf %>% show_best(metric = 'recall')
best_parameters_rf <- tree_tuning_rf %>% 
  select_best(metric = 'recall')
best_parameters_rf

#WF final
stroke_final_wf_rf <- stroke_wf_rf %>% 
  finalize_workflow(best_parameters_rf)

stroke_final_wf_rf

#Fit a Model
stroke_fit_rf <- stroke_final_wf_rf %>% 
  fit(stroke_imputed_train)

stroke_predictions_rf <- stroke_fit_rf %>% 
  predict(new_data = stroke_imputed_test) %>% 
  dplyr::bind_cols(stroke_imputed_test) %>% 
  dplyr::select(stroke, .pred_class)

head(stroke_predictions_rf)

#vemos el accurracy del tree
acc_tree_rf <- accuracy(
  data = stroke_predictions_rf,
  truth = stroke,
  estimate = .pred_class
)
acc_tree_rf

#vemos la matriz de confussion
conf_mat_tree_rf <- conf_mat(
  data = stroke_predictions_rf,
  truth = stroke,
  estimate = .pred_class
)
autoplot(conf_mat_tree_rf, "heatmap")

#Variables importantes
stroke_fit_rf <- stroke_fit_rf %>% 
  pull_workflow_fit()
vip(stroke_fit_rf)

parallel::stopCluster(parallel::makeCluster(8))
```

Si en cambio se utiliza precision o recall como métrica, se logra que el modelo empiece a predecir strokes pero cae la accuracy. En este caso esto se da porque hay una gran diferencia entre ambos escenarios posibles, por lo que lo ideal sería aumentar el costo. Respecto a la importancia de las variables, se puede ver que hubo un aumentó para las variables más importantes, con avg_glucose_level pasando a ser la más importante, age en segundo lugar y bmi se mantiene en tercer lugar pero con mucha mayor importancia.
