# How to cite

If RodentLimb contributes to published work, cite the app with the version you used, the pose model's software, and the data the model was trained on. The methods paragraph that RodentLimb exports already names the model, its parameters and the task references; add the citations below to your reference list.

## RodentLimb

> Shi, Z. (2026). *RodentLimb* (Version [used]) [Computer software]. https://seesaw-earth.github.io/RodentLimb/

```bibtex
@software{shi2026rodentlimb,
  author  = {Shi, Ziqing},
  title   = {RodentLimb: limb pose and behavior scoring for mouse videos},
  version = {1.4.2},
  year    = {2026},
  url     = {https://seesaw-earth.github.io/RodentLimb/}
}
```

Replace the version with the one shown under **RodentLimb › About RodentLimb**. The export manifest (`export_manifest.json`) records the app version and the model of every video.

## If you used CylinderPose7 (visible light) {#cylinderpose7}

| Cite | Why |
|---|---|
| RodentLimb, with version | Ran the model and computed your measures |
| Ultralytics YOLO26 (Jocher et al., 2026) | Network architecture, pretrained weights, training and export code |
| DeepLabCut (Mathis et al., 2018; Nath et al., 2019) | The teacher model that produced 20,000 of the training labels |
| COCO (Lin et al., 2014), recommended | The starting weights were pretrained on COCO keypoints |
| The laboratory's cylinder recordings | Training data; cite the dataset if it has been published |

Example methods sentence: *Pose was estimated on every frame with CylinderPose7 (CylinderMousePose v2.1, a YOLO26s-pose network distilled from a DeepLabCut model, half-precision Core ML; seven keypoints: four paws, tail base, nose and mouth) in RodentLimb [version] on macOS.*

## If you used PalmReaderPose8 (near-infrared) {#palmreaderpose8}

| Cite | Why |
|---|---|
| RodentLimb, with version | Ran the model and computed your measures |
| Ultralytics YOLO26 (Jocher et al., 2026) | Network architecture, pretrained weights, training and export code |
| Barkai et al. (2025) and the Zenodo record 10.5281/zenodo.16321240 | The human-labelled training frames come from their published DeepLabCut training set |
| Zhang et al. (2022) | The bottom-up near-infrared recording platform (Palmreader) |
| DeepLabCut (Mathis et al., 2018) | The labels were made in a DeepLabCut project |
| COCO (Lin et al., 2014), recommended | Pretraining of the starting weights |

Example methods sentence: *Pose was estimated on every frame with PalmReaderPose8 (a YOLO26s-pose network trained on the human-labelled frames of the bottom-up near-infrared DeepLabCut training set of Barkai et al., 2025; 8-bit Core ML) in RodentLimb [version] on macOS; its snout, tail base and four paw keypoints were used.*

## If you report a task

Each task page lists the protocol references behind its measures, and the exported `*_methods.txt` contains them with your parameter values. See [References](../reference/reading.md).

## References

- Barkai O., Zhang B., Lenfers Turnes B., Arab M., Yarmolinsky D.A., Zhang Z., Barrett L.B., Woolf C.J. (2025). A machine learning tool with light-based image analysis for automatic classification of 3D pain behaviors. *Cell Reports Methods* 5(9):101145. https://doi.org/10.1016/j.crmeth.2025.101145 (PubMed 40876461)
- DeepLabCut bottom-up 9-keypoint mouse tracking model and training set of Barkai et al. (2025) [Data set]. Zenodo. https://doi.org/10.5281/zenodo.16321240 (cite the record with the authors, title and version shown on Zenodo)
- Zhang Z., Roberson D.P., Kotoda M., Boivin B., Bohnslav J.P., González-Cano R., Yarmolinsky D.A., Lenfers Turnes B., Wimalasena N.K., Neufeld S.Q., Barrett L.B., Quintão N.L.M., Fattori V., Taub D.G., Wiltschko A.B., Andrews N.A., Harvey C.D., Datta S.R., Woolf C.J. (2022). Automated preclinical detection of mechanical pain hypersensitivity and analgesia. *Pain* 163(12):2326–2336. https://doi.org/10.1097/j.pain.0000000000002680
- Jocher G., Qiu J., Liu M., Lyu S., Akyon F.C., Kalfaoglu M.E. (2026). Ultralytics YOLO26: unified real-time end-to-end vision models. *arXiv* 2606.03748. https://doi.org/10.48550/arXiv.2606.03748 · Software: https://github.com/ultralytics/ultralytics (AGPL-3.0)
- Mathis A., Mamidanna P., Cury K.M., Abe T., Murthy V.N., Mathis M.W., Bethge M. (2018). DeepLabCut: markerless pose estimation of user-defined body parts with deep learning. *Nature Neuroscience* 21:1281–1289. https://doi.org/10.1038/s41593-018-0209-y
- Nath T., Mathis A., Chen A.C., Patel A., Bethge M., Mathis M.W. (2019). Using DeepLabCut for 3D markerless pose estimation across species and behaviors. *Nature Protocols* 14:2152–2176. https://doi.org/10.1038/s41596-019-0176-0
- Lin T.-Y. et al. (2014). Microsoft COCO: common objects in context. *ECCV 2014*, LNCS 8693:740–755. https://doi.org/10.1007/978-3-319-10602-1_48
- Apple Inc. (2025). *coremltools* (Version 9.0) [Computer software]. https://github.com/apple/coremltools (BSD-3-Clause)
